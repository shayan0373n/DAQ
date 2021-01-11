#include <TimerThree.h>
#include "DAQ.h"
/*
 * Digital Output In Order:
 * LSB
 * D3     PD0 
 * D2      
 * D0      
 * D1      
 * D4      
 * TXLED   30
 * D12     
 * D6      
 * 
 * RXLED    17
 * SCK --> ICSP 3 digital pin 15
 * MOSI --> ICSP 4 digital pin 16
 * MISO --> ICSP 1 digital pin 14
 * D8
 * D9
 * D10
 * D11    PB7
 * MSB
 */ 

void setup() {
	Serial.begin(256000);
	DDRF = (1 << CS_1) | (1 << CS_2) | (1 << CS_3) | (1 << CS_4) | (1 << OE); //CSs+OE pins
	PORTF = (1 << CS_1) | (1 << CS_2) | (1 << CS_3) | (1 << CS_4) | (1 << OE);
	pinMode(RD, OUTPUT);
	digitalWrite(RD, HIGH);
	PORTB = B11111111;
	DDRB = B00000000;
	PORTD = B11111111;
	DDRD = B00000000;
	attachInterrupt(digitalPinToInterrupt(BUSY), NEW_DATA, FALLING);
	while (!Serial); //it doesn't reset when you open the serial, so any serial output during the setup() function would be missed. Adding that line makes the board pause until you open the serial port, so you get to see that initial bit of data.
	while (Serial.readStringUntil('\n') != "hi"){};
	serialFlush();
	Serial.println("hi");

	bool flag = 1;
	do{
		while (!Serial.available()){};
		sampleRate = Serial.read();
		MODE = Serial.read();
		numberOfChannels = Serial.read();
		if (MODE>MAX_MODE || sampleRate>MAX_SR_RAT || numberOfChannels>MAX_NOC){
			Serial.println("NO");
			flag = 1;
		}
		else {
			Serial.println("OK");
			flag = 0;
		}
	} while (flag == 1);

	sampleRate = sampleRate*SR_BASE;

	event = bitRead(MODE, 0);
	slave = bitRead(MODE, 1);
	period = MEG / sampleRate;
	packetData = new byte[(numberOfChannels * 2 + event * 2)];
	Timer3.initialize(period); //microsecond
	while (Serial.readStringUntil('\n') != "start"){};
	Serial.println("start");
	if (!slave)
		Timer3.pwm(CONVST, (50.0 / 100) * 1024);
	serialFlush();
}

void loop() {
	while (!Serial.available()){ //BETTER TO USE IF(SERIAL.AVAILABLE()) AT THE END OF EACH ITTERATION? 
		byte i = 0;
		PORTF = FIRST_STATE; //B11110111 
		if (newData){ //wait for busy signal
			newData = 0;
			for (i = 0; i<numberOfChannels; i++){
				if (!(i % 8)){
					PORTF = (PORTF << 1) + 1;
				}
				digitalWrite(RD, LOW);
				DATA0 = PIND;
				DATA1 = PINB;
				packetData[0 + 2 * i] = DATA0;
				packetData[1 + 2 * i] = DATA1;
				digitalWrite(RD, HIGH);
			}
			if (event){
				PORTF = B11111101;
				packetData[2 * numberOfChannels] = PIND;
				packetData[2 * numberOfChannels + 1] = 0;
			}
			Serial.write(packetData, (numberOfChannels * 2 + event * 2));
		}

	}
	if (Serial.read() == XOFF){
		Timer3.disablePwm(CONVST); //Checkout this 
		while (Serial.read() != XON){}; //CHeckout this
		if (!slave)
			Timer3.pwm(CONVST, (50.0 / 100) * 1024);
		serialFlush(); // this cause serial.available=0
	}
}

inline void serialFlush(){
	while (Serial.available() > 0) {
		char t = Serial.read(); //NOT NECESSARY
	}
}  

void NEW_DATA(){
	newData = 1;
}

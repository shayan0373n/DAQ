#ifndef DAQ
#define DAQ

#define MEG 1048576 // pow(2,20) 

#define OE   1  
#define CS_1 4  
#define CS_2 5  
#define CS_3 6  
#define CS_4 7
#define XOFF 19
#define XON  17

#define FIRST_STATE B11110111

#define CONVST 5 
#define RD     13
#define BUSY   7

#define MAX_NOC 32
#define MAX_MODE 3
#define MAXIMUM_SAMPLE_RATE 2048

#define SR_BASE 256
#define MAX_SR_RAT (MAXIMUM_SAMPLE_RATE/SR_BASE)

byte numberOfChannels = 0; //INITIALIZATION
byte MODE = 0;
byte newData = 0;
uint8_t DATA0;
int8_t DATA1;
unsigned int sampleRate = 0;
unsigned int long period = MEG / SR_BASE;
bool event=0;
bool slave=0;
byte *packetData; 

void serialFlush(); 
#endif 

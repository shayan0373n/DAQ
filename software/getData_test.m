clear
close all
figure
ax = axes();
daq1 = DAQ(32, 1024, 0, 0);
daq1.start;
while(daq1.isRunning)
    daq1.available
    if daq1.available > 512
        data = daq1.get_data(512);
        data_fft = fft(data(:,5));
        plot(ax, 20*log(abs(data_fft(1:256))));
        ylim([-200 50]);
        xlim([0 256]);
    end
end

daq1.stop;

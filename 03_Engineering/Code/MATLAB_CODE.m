%Arduino detected.
%This device is ready for use with MATLAB Support Package for Arduino Hardware. Get started with examples and other documentation.
%This device is ready for use with Simulink Support Package for Arduino Hardware. Get started with examples and other documentation.
%MATLAB Code:
% Collecting, filtering and plotting ECG signals
clear;
clc;
close all;
% Enter your Arduino COM port here
arduino = serialport("COM5", 115200);
% Allow the Arduino to restart
pause(2);
% Clear any old data
flush(arduino);
% Number of samples taken every second
sampleRate = 250;
% Collect data for 10 seconds
recordingTime = 10;
% Calculate the total number of samples
totalSamples = sampleRate * recordingTime;
% Create empty arrays to store the data
ECG = zeros(totalSamples,1);
LOminus = zeros(totalSamples,1);
LOplus = zeros(totalSamples,1);
disp("Recording ECG signal...");
for i = 1:totalSamples
% Read one line from the Arduino
data = readline(arduino);
% Separate the three values
values = sscanf(data,'%f,%f,%f');
% Check that all three values have arrived
if length(values) == 3
ECG(i) = values(1);
LOminus(i) = values(2);
LOplus(i) = values(3);
else
% Ignore an invalid measurement
ECG(i) = NaN;
LOminus(i) = NaN;
LOplus(i) = NaN;
end
end
% Close the serial connection
clear arduino;
disp("Recording complete!");
% Check whether either electrode disconnected
if any(LOminus == 1) || any(LOplus == 1)
warning("Electrode disconnection detected! Check the ECG electrodes.");
else
disp("Both electrode connections appear to be stable.");
end
% Create a time value for every ECG measurement
time = (0:totalSamples-1) / sampleRate;
% Find valid ECG measurements
validData = ~isnan(ECG);
% Keep only valid measurements
ECG = ECG(validData);
time = time(validData);
% Update the total number of valid samples
totalSamples = length(ECG);
% Set the lower and upper filter frequencies
lowFrequency = 0.5;
highFrequency = 40;
% Create a fourth-order Butterworth bandpass filter
[b,a] = butter(4, ...
[lowFrequency highFrequency]/(sampleRate/2), ...
'bandpass');
% Remove low-frequency and high-frequency noise
filteredECG = filtfilt(b,a,ECG);
windowSize = 10;
smoothedECG = movmean(filteredECG, windowSize);
figure;
subplot(2,1,1);
plot(time,ECG);
title('Original ECG Signal');
xlabel('Time (seconds)');
ylabel('ADC Reading');
grid on;
subplot(2,1,2);
plot(time,smoothedECG);
title('Filtered ECG Signal');
xlabel('Time (seconds)');
ylabel('Amplitude (ADC units)');
grid on;
% Estimate the minimum distance between heartbeats
minimumDistance = round(0.3 * sampleRate);
% Set the minimum peak prominence
minimumProminence = 3 * std(filteredECG);
% Find the R peaks
[peakValues,peakLocations] = findpeaks(filteredECG, ...
'MinPeakDistance',minimumDistance, ...
'MinPeakProminence',minimumProminence);
pSearchStart = 0.30; %Earliest point at which P wave is expected before R wave
pSearchEnd = 0.06; %Last poit at which the P wave is expected (Stop before Q wave)
pPeakTimes = NaN(size(peakLocations)); % array of NA same size as array for pealLocations of R wave
pPeakvalues = NaN(size(peakValues)); % array of NA same size as array for peakvalues of R waves
for k = 1:numel(peakLocations)
s = peakLocations(k) - round(pSearchStart * sampleRate); %Start P peak search at this value
e = peakLocations(k) - round(pSearchEnd * sampleRate); % end P peak search at this value
    if s < 1, continue; %stops looking for P wave before recorded data
    end
[pPeakvalues(k),i] = max(smoothedECG(s:e)); % reduces filteredECG to within desired range, stores in k element of pPeakValue
pPeakTimes = time(s + i - 1);
end
% Convert peak locations into time
peakTimes = time(peakLocations);
% Calculate the time between consecutive R peaks
RRintervals = diff(peakTimes);
% Calculate heart rate in beats per minute
if length(RRintervals) >= 1
heartRate = 60 ./ RRintervals;
% Calculate average heart rate
averageHeartRate = mean(heartRate);
disp("Average heart rate:");
disp(averageHeartRate);
else
averageHeartRate = NaN;
warning("Not enough R peaks detected to calculate heart rate.");
end

if mean(heartRate) < 50
    disp("Bradycardia detected");
elseif mean(heartRate) >80
    disp("Tachycardia detected");
else 
    disp("Heart rate normal");
end 

figure;
plot(time,smoothedECG);
hold on;
plot(peakTimes,peakValues,'ro','MarkerFaceColor','r');
title('Filtered ECG with Detected R Peaks');
xlabel('Time (seconds)');
ylabel('Amplitude (ADC units)');
legend('Filtered ECG','R Peaks');
grid on;
figure;
plot(time,smoothedECG);
hold on;
plot(pPeakTimes,pPeakvalues,'ro','MarkerFaceColor','b');
title('Filtered ECG with Detected P Peaks');
xlabel('Time (seconds)');
ylabel('Amplitude (ADC units)');
legend('Filtered ECG','R Peaks');
grid on;
figure;
% Display the first three seconds
plot(time,smoothedECG);
xlim([0 min(3,time(end))]);
title('Detailed ECG Waveform - PQRST');
xlabel('Time (seconds)');
ylabel('Amplitude (ADC units)');
grid on;
disp("ECG processing finished!")

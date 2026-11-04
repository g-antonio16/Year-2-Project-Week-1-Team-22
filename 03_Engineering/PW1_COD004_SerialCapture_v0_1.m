% PW1-COD-004  Record ECG live from the Arduino + AD8232 over USB serial
% Rev 0.1  03/11/2026
%
% Expects the PW1 Arduino sketch, which sends one line per sample:
%     <time in microseconds>,<ADC value>,<lead-off flag>     e.g.  1234567,512,0
%
% Shows a scrolling live plot, then saves the recording to
% 08_Data_Records/Lab_Recordings as a .mat file with ecg (mV), t (s) and Fs,
% the same format COD-002 reads. Close the plot window to stop early.
%
% Base MATLAB only (serialport is built in, no toolbox needed).

clear; clc; close all;

%% 1. Settings - fill these in before every recording
dataID    = 'DAT-007';     % next free ID from the Data Record Log (REC-006)
label     = 'LabRest';     % short CamelCase description, e.g. LabRest, LabArmMovement
duration  = 30;            % seconds to record
port      = "";            % leave "" to auto-pick, or e.g. "/dev/cu.usbmodem14101"
baud      = 115200;        % must match Serial.begin() in the Arduino sketch

% ADC -> mV conversion (CONFIRM AT KIT HANDOUT)
Vref      = 5;             % Arduino analog reference voltage (V): Uno = 5, ESP32/Nano 33 = 3.3
adcMax    = 1023;          % 10-bit ADC = 1023, 12-bit ADC = 4095
boardGain = 1100;          % AD8232 board total gain (check the SparkFun datasheet)

windowSec = 5;             % seconds shown in the live plot

%% 2. Output file (refuse to reuse a Data ID)
qmsRoot = fileparts(fileparts(fileparts(which('PW1_COD004_SerialCapture_v0_1'))));
dataRoot = fullfile(qmsRoot, '08_Data_Records');
outDir   = fullfile(dataRoot, 'Lab_Recordings');
if ~isempty(dir(fullfile(dataRoot, '**', ['*' dataID '_*'])))
    error('%s is already used. Take the next free ID from the Data Record Log.', dataID);
end
outName = sprintf('%s_PW1_%s_%s_v1-0.mat', datestr(now, 'yyyymmdd'), dataID, label);

%% 3. Open the serial port
if port == ""
    ports = serialportlist("available");
    ports = ports(contains(ports, "usb", 'IgnoreCase', true) & ~contains(ports, "/dev/tty."));
    if isempty(ports)
        error('No Arduino found. Plug it in, close the Arduino Serial Monitor, then run again.');
    elseif numel(ports) > 1
        error('Several ports found: %s\nSet "port" in the settings to the right one.', strjoin(ports, ', '));
    end
    port = ports(1);
end
fprintf('Opening %s at %d baud...\n', port, baud);
s = serialport(port, baud);
cleanup = onCleanup(@() delete(s));   % always release the port, even after an error or Ctrl+C

pause(2);                             % opening the port resets an Uno; let it restart
flush(s);                             % throw away anything sent while it was starting

%% 4. Record with a live plot
maxN    = ceil(duration * 2000);      % generous pre-allocation (up to 2 kHz)
tUs     = zeros(maxN, 1);             % Arduino timestamps (microseconds)
counts  = zeros(maxN, 1);             % raw ADC values
leadOff = zeros(maxN, 1);             % 1 = an electrode is off
n       = 0;
buf     = '';
firstLine = true;

fig = figure('Name', ['Recording ' dataID ' - close this window to stop early']);
h = plot(NaN, NaN, 'b'); grid on;
xlabel('Time (s)'); ylabel('ADC counts');
title(sprintf('%s live (%s)', dataID, label));

fprintf('Recording for %g s...\n', duration);
tic; lastDraw = 0;
while toc < duration && isvalid(fig)
    nb = s.NumBytesAvailable;
    if nb > 0
        buf = [buf, char(read(s, nb, 'uint8'))]; %#ok<AGROW>
        last = find(buf == newline, 1, 'last');  % only parse complete lines
        if ~isempty(last)
            chunk = buf(1:last);
            buf   = buf(last+1:end);
            if firstLine                         % first line is usually cut in half
                chunk = chunk(find(chunk == newline, 1) + 1:end);
                firstLine = false;
            end
            % whole lines only, so a corrupted line is skipped rather than misread
            tok = regexp(chunk, '^(\d+),(\d+),([01])\r?$', 'tokens', 'lineanchors');
            if ~isempty(tok)
                v = str2double(vertcat(tok{:}));    % k x 3: time, value, lead-off
                k = size(v, 1);
                if n + k > maxN, break; end
                tUs(n+1:n+k)     = v(:, 1);
                counts(n+1:n+k)  = v(:, 2);
                leadOff(n+1:n+k) = v(:, 3);
                n = n + k;
            end
        end
    end

    % refresh the plot about 10 times a second
    if n > 1 && toc - lastDraw > 0.1
        tNow = (tUs(1:n) - tUs(1)) / 1e6;
        keep = tNow > tNow(end) - windowSec;
        set(h, 'XData', tNow(keep), 'YData', counts(keep));
        drawnow limitrate;
        lastDraw = toc;
    else
        pause(0.005);                            % let serial data build up
    end
end
clear cleanup;                                   % close the serial port
if n < 2, error('No data received. Check the baud rate and that the Arduino sketch is running.'); end

tUs = tUs(1:n); counts = counts(1:n); leadOff = leadOff(1:n);

%% 5. Timing check (validation evidence)
dtUs = diff(tUs);
dtUs(dtUs < 0) = dtUs(dtUs < 0) + 2^32;          % micros() wraps after ~70 min
t    = [0; cumsum(dtUs)] / 1e6;                  % seconds from start
Fs   = 1e6 / median(dtUs);
gaps = sum(dtUs > 1.5 * median(dtUs));           % samples lost on the serial link

fprintf('\nSamples: %d   Duration: %.2f s\n', n, t(end));
fprintf('Sampling rate: %.2f Hz (median)   Jitter: %.1f us   Gaps: %d\n', Fs, std(dtUs), gaps);
fprintf('Lead-off: %.1f %% of samples\n', 100 * mean(leadOff));
if gaps > 0,              warning('%d gaps in the data - serial link dropped samples.', gaps); end
if mean(leadOff) > 0.05,  warning('Electrode contact was lost for over 5%% of the recording.'); end

%% 6. Convert to mV and save
Vout = counts * Vref / adcMax;                   % volts at the AD8232 output
ecg  = Vout / boardGain * 1000;                  % mV at the skin (offset removed later by COD-002)

settings = struct('port', char(port), 'baud', baud, 'Vref', Vref, 'adcMax', adcMax, ...
    'boardGain', boardGain, 'recordedOn', datestr(now), 'jitter_us', std(dtUs), 'gaps', gaps);
save(fullfile(outDir, outName), 'ecg', 't', 'Fs', 'counts', 'leadOff', 'tUs', 'settings');
fprintf('\nSaved %s\nAdd %s to the Data Record Log, then analyse it with COD-002 (dataID = ''%s'').\n', ...
    outName, dataID, dataID);

figure('Name', [dataID ' full recording']);
plot(t, ecg); grid on;
xlabel('Time (s)'); ylabel('Amplitude (mV)');
title(sprintf('%s %s  (Fs = %.1f Hz)', dataID, label, Fs));

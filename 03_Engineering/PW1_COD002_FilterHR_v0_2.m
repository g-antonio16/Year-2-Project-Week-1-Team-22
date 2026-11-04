% PW1-COD-002  Filter one ECG recording, detect R-peaks and measure heart rate
% Rev 0.2  03/11/2026  - analyses one file at a time (chosen by Data ID)
%
% Uses base MATLAB only (no Signal Processing Toolbox), so it also runs on
% the lab PCs.
%
% Filter chain (all zero-phase, forward + backward):
%   1. 4th-order Butterworth high-pass  - removes baseline wander / DC offset
%   2. Notch at 50 Hz and 60 Hz         - removes mains (powerline) hum
%   3. 4th-order Butterworth low-pass   - removes high-frequency EMG noise
%
% If the file is simulated, the clean export (DAT-002) is used as ground
% truth to report SNR before and after filtering. True heart rate is read
% from the file name if it contains e.g. "72bpm".

clear; clc; close all;

%% 1. Settings - choose the file and the filter design
dataID     = 'DAT-003';  % which recording to analyse (see Data Record Log REC-006)
hpCut      = 0.5;        % Hz  high-pass cut-off (baseline wander is < 0.5 Hz)
lpCut      = 40;         % Hz  low-pass cut-off (most QRS energy is < 40 Hz)
notchFreqs = [50 60];    % Hz  mains frequencies (simulator adds both)
cleanID    = 'DAT-002';  % clean simulated reference

%% 2. Find the folders and the data file
qmsRoot  = fileparts(fileparts(fileparts(which('PW1_COD002_FilterHR_v0_2'))));
dataRoot = fullfile(qmsRoot, '08_Data_Records');
figDir   = fullfile(qmsRoot, '09_Analysis_and_Results', 'Figures');
repDir   = fullfile(qmsRoot, '09_Analysis_and_Results', 'Reports');
stamp    = datestr(now, 'yyyymmdd');

match = dir(fullfile(dataRoot, '**', ['*' dataID '_*.mat']));   % ** = search subfolders
if isempty(match), error('No file for %s found under %s', dataID, dataRoot); end
if numel(match) > 1, error('More than one file matches %s - Data IDs must be unique.', dataID); end
dataFile = fullfile(match.folder, match.name);
fprintf('Analysing %s\n', match.name);

%% 3. Load the signal
[x, Fs] = loadECG(dataFile);
x = x - mean(x);                       % remove DC offset so raw and filtered are comparable
t = (0:numel(x)-1)' / Fs;              % time axis in seconds

%% 4. Filter
y = ecgFilter(x, Fs, hpCut, lpCut, notchFreqs);

%% 5. Detect R-peaks and calculate heart rate
r = detectR(y, Fs);                    % sample indices of each R-peak
hr = NaN;
if numel(r) > 1
    rr = diff(r) / Fs;                 % R-R intervals in seconds
    hr = 60 / mean(rr);                % beats per minute
end
trueHR = NaN;
tok = regexp(match.name, '(\d+)bpm', 'tokens', 'once');
if ~isempty(tok), trueHR = str2double(tok{1}); end

%% 6. Signal quality against the clean reference (simulated data only)
snrRaw = NaN; snrFilt = NaN; c = [];
ref = dir(fullfile(dataRoot, 'Simulated', ['*' cleanID '_*.mat']));
if contains(match.folder, 'Simulated') && ~isempty(ref) && ~strcmp(dataID, cleanID)
    [clean, cleanFs] = loadECG(fullfile(ref(1).folder, ref(1).name));
    if cleanFs == Fs
        n = min(numel(x), numel(clean));
        c = clean(1:n) - mean(clean(1:n));
        snrRaw  = snrdB(c, x(1:n));
        snrFilt = snrdB(c, y(1:n));
    end
end

%% 7. Plot raw vs filtered
fig = figure('Name', dataID, 'Position', [100 100 900 550]);
subplot(2, 1, 1);
plot(t, x, 'Color', [0.5 0.5 0.5]); grid on;
title(sprintf('%s raw  (Fs = %g Hz)', dataID, Fs));
ylabel('Amplitude (mV)');

subplot(2, 1, 2);
plot(t, y, 'b'); hold on; grid on;
if ~isempty(c), plot(t(1:numel(c)), c, 'k--'); end
plot(t(r), y(r), 'ro', 'MarkerFaceColor', 'r');
ttl = sprintf('Filtered (HP %g Hz, notch %s Hz, LP %g Hz)  |  %d beats, HR = %.1f bpm', ...
    hpCut, strjoin(string(notchFreqs), '/'), lpCut, numel(r), hr);
if ~isnan(snrRaw), ttl = sprintf('%s  |  SNR %.1f -> %.1f dB', ttl, snrRaw, snrFilt); end
title(ttl);
xlabel('Time (s)'); ylabel('Amplitude (mV)');
if ~isempty(c), legend('Filtered', 'Clean reference', 'R-peaks'); else, legend('Filtered', 'R-peaks'); end
saveas(fig, fullfile(figDir, sprintf('%s_PW1_FIG_%s_Filtered_v1-0.png', stamp, dataID)));

%% 8. Print and save the results
result = table({dataID}, {match.name}, Fs, numel(x)/Fs, numel(r), hr, trueHR, hr - trueHR, ...
    snrRaw, snrFilt, snrFilt - snrRaw, hpCut, lpCut, {strjoin(string(notchFreqs), '/')}, ...
    'VariableNames', {'DataID', 'File', 'Fs_Hz', 'Duration_s', 'Beats', 'HR_bpm', 'TrueHR_bpm', ...
    'HRError_bpm', 'SNRraw_dB', 'SNRfiltered_dB', 'SNRgain_dB', 'HPcut_Hz', 'LPcut_Hz', 'Notch_Hz'});
disp(result(:, {'DataID', 'Beats', 'HR_bpm', 'TrueHR_bpm', 'HRError_bpm', 'SNRraw_dB', 'SNRfiltered_dB'}));

% Append to one running results log so every run is recorded
logFile = fullfile(repDir, 'PW1_REP-001_FilterHRResults.csv');
if isfile(logFile)
    writetable([readtable(logFile, 'TextType', 'char'); result], logFile);
else
    writetable(result, logFile);
end
fprintf('Result added to %s\n', logFile);


%% ------------------------------------------------------------------------
%  Local functions
%  ------------------------------------------------------------------------
function [x, Fs] = loadECG(f)
% Accepts simulator exports (Time, Signal) and COD-001 crops (ecg, t, Fs).
    S = load(f);
    if isfield(S, 'Signal') && isfield(S, 'Time')
        x  = double(S.Signal(:));
        Fs = 1 / median(diff(double(S.Time(:))));
        Fs = round(Fs * 1000) / 1000;
    elseif isfield(S, 'ecg') && isfield(S, 'Fs')
        x  = double(S.ecg(:));
        Fs = double(S.Fs);
    else
        error('%s: expected variables Time+Signal or ecg+Fs.', f);
    end
end

function y = ecgFilter(x, Fs, hpCut, lpCut, notchFreqs)
    y = x(:);
    for Q = [0.5412 1.3066]                        % 4th-order Butterworth = 2 biquads
        [b, a] = biquad('hp', hpCut, Fs, Q); y = zeroPhase(b, a, y, Fs);
    end
    for f0 = notchFreqs
        if f0 < Fs/2, [b, a] = biquad('notch', f0, Fs, 30); y = zeroPhase(b, a, y, Fs); end
    end
    if lpCut < Fs/2
        for Q = [0.5412 1.3066]
            [b, a] = biquad('lp', lpCut, Fs, Q); y = zeroPhase(b, a, y, Fs);
        end
    end
end

function [b, a] = biquad(kind, f0, Fs, Q)
% Second-order filter sections (bilinear transform, RBJ audio-EQ formulas)
    w0 = 2*pi*f0/Fs; c = cos(w0); al = sin(w0)/(2*Q);
    a = [1+al, -2*c, 1-al];
    switch kind
        case 'hp',    b = [(1+c)/2, -(1+c), (1+c)/2];
        case 'lp',    b = [(1-c)/2, 1-c, (1-c)/2];
        case 'notch', b = [1, -2*c, 1];
    end
    b = b / a(1); a = a / a(1);
end

function y = zeroPhase(b, a, x, Fs)
% Forward-backward filtering (no phase delay, so R-peaks stay in place).
% Mirror-pads the ends so the filter does not ring at the start/end.
    n  = min(numel(x) - 1, round(2 * Fs));
    xp = [x(n+1:-1:2); x; x(end-1:-1:end-n)];
    y  = filter(b, a, xp);
    y  = flipud(filter(b, a, flipud(y)));
    y  = y(n+1:n+numel(x));
end

function r = detectR(y, Fs)
% Simplified Pan-Tompkins: slope energy -> threshold -> largest peak in window
    d = [0; diff(y)];
    e = movmean(d.^2, round(0.15 * Fs));               % 150 ms integration window
    es = sort(e);
    thr = 0.3 * es(floor(0.99 * (numel(e) - 1)) + 1);  % 30% of 99th percentile
    above  = e > thr;
    starts = find(diff([0; above]) == 1);
    ends   = find(diff([above; 0]) == -1);

    pol = 1; if max(y) < -min(y), pol = -1; end        % handle inverted leads
    w = round(0.075 * Fs);
    r = zeros(numel(starts), 1);
    for k = 1:numel(starts)
        lo = max(1, starts(k) - w); hi = min(numel(y), ends(k) + w);
        [~, i] = max(pol * y(lo:hi));
        r(k) = lo + i - 1;
    end
    r = unique(r);

    keep = [];                                          % 250 ms refractory period
    for i = r'
        if ~isempty(keep) && i - keep(end) < 0.25 * Fs
            if pol * y(i) > pol * y(keep(end)), keep(end) = i; end
        else
            keep(end+1) = i; %#ok<AGROW>
        end
    end
    r = keep(:);
end

function s = snrdB(ref, x)
    s = 10 * log10(var(ref) / var(x(:) - ref(:)));
end

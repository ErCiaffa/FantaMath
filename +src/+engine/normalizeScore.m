function score = normalizeScore(raw, alpha, pLow, pHigh)
%NORMALIZESCORE FORM-01: log + percentile normalization, relative to the current listone.
%
% score = normalizeScore(raw, alpha, pLow, pHigh) implements spec step 1 exactly:
%   rawLog = log(1 + alpha .* raw)
%   lo = percentile(rawLog, pLow*100), hi = percentile(rawLog, pHigh*100)
%   score = clip((rawLog - lo) / (hi - lo), 0, 1)
%
% Degenerate case (hi <= lo, e.g. a listone where every FVM/QUOT is identical) returns a
% zero vector of the same size as raw, never NaN/Inf.
%
% Named normalizeScore (not "normalize") to avoid shadowing MATLAB's built-in normalize().
    arguments
        raw (:,1) double
        alpha (1,1) double {mustBePositive}
        pLow (1,1) double {mustBeInRange(pLow, 0, 1)}
        pHigh (1,1) double {mustBeInRange(pHigh, 0, 1)}
    end

    if exist('prctile', 'file') ~= 2
        error('FantaMath:env:missingToolbox', ...
            ['Statistics and Machine Learning Toolbox non disponibile: la funzione prctile ' ...
             'e'' richiesta da normalizeScore (FORM-01) e non risulta installata/licenziata.']);
    end

    rawLog = log(1 + alpha .* raw);
    lo = prctile(rawLog, pLow * 100);
    hi = prctile(rawLog, pHigh * 100);

    if hi <= lo
        score = zeros(size(rawLog));
        return
    end

    score = min(max((rawLog - lo) ./ (hi - lo), 0), 1);
end

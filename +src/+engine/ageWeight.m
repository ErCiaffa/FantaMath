function w = ageWeight(ages, params)
%AGEWEIGHT Additive eta term for assembleWeight: valore = S * (1 + mod + duttilita + eta).
%
% w = ageWeight(ages, params) returns, for each player i, a linear "youth bonus" ramp --
% no old-age malus (2026-08-03 decision: removed entirely, bonus only, never negative):
%   w_i = etaBonusMax                                              if age_i <= etaFloor
%       = etaBonusMax * (etaZero - age_i) / (etaZero - etaFloor)   if etaFloor < age_i < etaZero
%       = 0                                                        if age_i >= etaZero (or NaN)
%
% etaFloor (default 15): youngest age Serie A actually allows, so the bonus caps there
% instead of growing further for a hypothetically younger age. etaZero (default 38): age at
% which the bonus fades out completely and stays at 0 (clamped, never goes negative).
    arguments
        ages (:,1) double
        params (1,1) struct
    end

    ages = double(ages);
    n = numel(ages);
    w = zeros(n, 1);

    valid = ~isnan(ages);
    atFloor = valid & ages <= params.etaFloor;
    ramp = valid & ages > params.etaFloor & ages < params.etaZero;

    w(atFloor) = params.etaBonusMax;
    w(ramp) = params.etaBonusMax * (params.etaZero - ages(ramp)) / (params.etaZero - params.etaFloor);
    % ages >= etaZero (or NaN) stay at 0 -- already the default.
end

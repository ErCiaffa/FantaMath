function credito = auctionPrice(assembleWeight, owned, totalBudget, offsetC, expK, floorCredito)
%AUCTIONPRICE Final conversion of assembleWeight into league credits (2026-08-04 decision).
%
% credito = auctionPrice(assembleWeight, owned, totalBudget, offsetC, expK, floorCredito)
%
%   shifted = (assembleWeight + offsetC) .^ expK
%   credito = max(floorCredito, shifted * totalBudget / sum(shifted(owned)))
%
% The offset (offsetC, added BEFORE the exponent) avoids the pathology of a bare power curve
% (assembleWeight^k), which crushes every low value toward zero ever harder as k grows --
% verified on real data: a bare k=2.8-3.2 needed to reach a 100-150 credit top squeezes
% roughly half the roster into one narrow low band (e.g. 144/313 players landed in the same
% 6-10 credit band). Shifting first, then raising to power, spreads the low end out again
% while still letting the top separate (see docs/decisioni-e-logica.md, 2026-08-04).
%
% totalBudget: sum(creditiIniziali across teams) * (1+epsilon) -- the money actually in
% play. The rescale ratio is computed ONLY over `owned` players (that's the pool the budget
% is actually spent on); free agents still get a value for reference/comparison, using the
% same ratio, but are not part of the sum-equals-budget constraint.
% floorCredito: minimum credit for anyone (dignity floor, e.g. reserve keepers at S=0).
    arguments
        assembleWeight (:,1) double
        owned (:,1) logical
        totalBudget (1,1) double {mustBePositive}
        offsetC (1,1) double {mustBeNonnegative}
        expK (1,1) double {mustBePositive}
        floorCredito (1,1) double {mustBeNonnegative}
    end
    shifted = (assembleWeight + offsetC) .^ expK;
    denom = sum(shifted(owned));
    if denom <= 0
        credito = max(floorCredito, zeros(size(assembleWeight)));
        return
    end
    credito = max(floorCredito, shifted * totalBudget / denom);
end

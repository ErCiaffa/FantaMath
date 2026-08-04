function valueAssembled = assembleWeight(score, mod, duttilita, etaWeight)
%ASSEMBLEWEIGHT Final additive assembly, decided 2026-08-03/04 (see docs/decisioni-e-logica.md):
%   valueAssembled = S * (1 + mod + duttilita + eta)
%
% Pure additive combination -- NOT (1+mod+duttilita)*(1+eta) or any other multiplicative
% split. Reason (explicit decision): additive keeps the maximum possible total bonus always
% equal to the sum of each term's own cap (predictable), while multiplicative compounding
% makes the real maximum grow every time a new term is added -- the same kind of
% "ribaltamento" (ranking flip) risk already rejected once for rho=1 in roleFactor.
%
% score: S (0-1), the FVM/QUOT-mixed player score.
% mod: additive role modifier, roleOverride-1 (see roleMod.m) -- NOT scarcity-weighted.
% duttilita: additive multi-role bonus, Flex-1 (see roleFactor.m).
% etaWeight: additive age bonus (see ageWeight.m), always >= 0.
    arguments
        score (:,1) double
        mod (:,1) double
        duttilita (:,1) double
        etaWeight (:,1) double
    end
    valueAssembled = score .* (1 + mod + duttilita + etaWeight);
end

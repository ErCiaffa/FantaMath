function S = mixScores(fScore, qScore, phi)
%MIXSCORES FORM-02: weighted mix of F_score/Q_score.
%
% S = mixScores(fScore, qScore, phi) implements spec step 2 exactly:
%   S = phi .* fScore + (1 - phi) .* qScore
%
% phi = 1 reproduces fScore exactly; phi = 0 reproduces qScore exactly.
    arguments
        fScore (:,1) double
        qScore (:,1) double
        phi (1,1) double {mustBeInRange(phi, 0, 1)}
    end

    S = phi .* fScore + (1 - phi) .* qScore;
end

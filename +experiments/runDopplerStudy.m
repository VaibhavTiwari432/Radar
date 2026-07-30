function runDopplerStudy(episodes)
%RUNDOPPLERSTUDY  The whole item-1 experiment, end to end, in one call.
%
%   experiments.runDopplerStudy(episodes)
%
%   Two arms, identical except for the reward-shaping term, so the effect of
%   shaping is attributable:
%       shaped  : terminal ladder + potential-based shaping (Ng et al. 1999)
%       noshape : terminal ladder only  (the CONTROL for "sparse terminal
%                 rewards never propagated")
%
%   Both run on agent.buildEnvDoppler, which has the measured Doppler axis.
%   The legacy 300-episode curve in results/feature_agent.mat is the third
%   comparison point and is read, not re-run -- it is a published result.

    if nargin < 1 || isempty(episodes); episodes = 1200; end

    fprintf('=== Doppler study: %d episodes per arm ===\n', episodes);
    t0 = tic;
    experiments.trainDopplerAgent(episodes, 1, true,  'shaped');
    fprintf('--- arm 1 done at %.1f min ---\n', toc(t0)/60);
    experiments.trainDopplerAgent(episodes, 1, false, 'noshape');
    fprintf('=== study complete in %.1f min ===\n', toc(t0)/60);
end

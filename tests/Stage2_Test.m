classdef Stage2_Test < matlab.unittest.TestCase
%STAGE2_TEST  Range-Doppler processing & detections (POA Part 4, Stage 2).
%
%   STATUS: SPEC / SCAFFOLD. Reports Incomplete until +radar/rangeDoppler.m
%   exists. The assertions below are the contract your local loop implements
%   against.
%
%   Intended contract (implement in +radar/rangeDoppler.m):
%       [rdMap, rangeAxis, dopAxis] = radar.rangeDoppler(rxCube, wav, C)
%         rxCube    : [fastTime x numPulses] complex, slow-time stacked
%         wav       : the transmit waveform (phased.* object)
%         C         : physics.Constants()
%         rdMap     : real, non-negative range-Doppler power map
%         rangeAxis : [numRange x 1] metres  (scale = C.range_per_sample)
%         dopAxis   : [numDop x 1]   Hz or m/s
%
%   Claim under test: a moving real target lands on the correct range-Doppler
%   cell; a naive time-delayed phantom sits at ~zero Doppler (a giveaway the
%   synthesizer must later fix).

    methods (TestMethodSetup)
        function requireImpl(tc)
            tc.assumeTrue(localHas('radar.rangeDoppler'), ...
                'Stage 2 pending: implement +radar/rangeDoppler.m (spec in this file).');
        end
    end

    methods (Test)

        function test_output_contract(tc)
            C = physics.Constants();
            wav = phased.LinearFMWaveform('SampleRate',C.fs,'PulseWidth',12e-6, ...
                    'PRF',50e3,'SweepBandwidth',2e6);
            numPulses = 32; fastTime = 256;
            cube = (randn(fastTime,numPulses)+1i*randn(fastTime,numPulses))/sqrt(2);
            [rd, rax, dax] = radar.rangeDoppler(cube, wav, C);
            tc.verifyTrue(isreal(rd) && all(rd(:) >= 0), 'RD map must be real & non-negative.');
            tc.verifyEqual(size(rd), [numel(rax) numel(dax)], ...
                'RD map size must match [range x doppler] axes.');
        end

        function test_moving_target_on_correct_cell(tc)
            % Inject a target at a known range bin with nonzero Doppler and
            % check the RD peak lands there (within a couple of cells).
            C = physics.Constants();
            wav = phased.LinearFMWaveform('SampleRate',C.fs,'PulseWidth',12e-6, ...
                    'PRF',50e3,'SweepBandwidth',2e6);
            fastTime = 256; numPulses = 32; rbin = 120; fd = 4;  % doppler bin
            cube = 0.05*(randn(fastTime,numPulses)+1i*randn(fastTime,numPulses));
            n = (0:numPulses-1);
            cube(rbin,:) = cube(rbin,:) + exp(1i*2*pi*fd*n/numPulses); % moving target
            [rd, ~, dax] = radar.rangeDoppler(cube, wav, C);
            [~, iMax] = max(rd(:));
            [rPk, dPk] = ind2sub(size(rd), iMax);
            tc.verifyLessThanOrEqual(abs(rPk - rbin), 3, 'Range peak off by >3 cells.');
            tc.verifyGreaterThan(abs(dax(dPk)), 0, 'Moving target should not be at zero Doppler.');
        end

    end

end

% ===================== file-local helpers =============================
function tf = localHas(name)
    tf = ~isempty(which(name));
end

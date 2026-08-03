function d = cfarDefaults()
%CFARDEFAULTS  The judge's detector operating point, declared ONCE.
%
%   d = radar.cfarDefaults()
%
%   Read by +radar/cfarDetect.m (which applies them) and by any reporting
%   layer that needs to state what the detector was configured with
%   (+missionsim/buildFrameLog.m). Before this existed, buildFrameLog read
%   the design Pfa out of the exported .mat -- i.e. out of a file the
%   ADVERSARY's exporter writes (Phase A1). The judge's own settings are
%   not the adversary's to declare, not even for display.
%
%   Pfa = 1e-4: POA Part 4 Stage 1's design false-alarm rate. NumTraining
%   20 / NumGuard 4 per cell side (phased.CFARDetector takes them doubled,
%   see cfarDetect.m).

    d = struct('Pfa', 1e-4, 'NumTraining', 20, 'NumGuard', 4, 'Method', 'CA');
end

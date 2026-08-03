function [Rapp, ambigOrder, Rua] = apparentRange(rangeM, prfHz)
%APPARENTRANGE  Where a beyond-R_ua echo ACTUALLY appears to the radar.
%
%   [Rapp, ambigOrder, Rua] = physics.apparentRange(rangeM, prfHz)
%       Rapp       : apparent (folded) range [m], in [0, Rua)
%       ambigOrder : how many PRIs late the echo is (0 = unambiguous)
%       Rua        : c/(2*PRF), the unambiguous range for this PRF
%
%   A pulse radar re-arms its range gate every PRI. An echo from beyond
%   R_ua = c*PRI/2 arrives AFTER the next pulse has gone out, so the
%   receiver times it from the wrong transmission and records it at
%   mod(R, R_ua). This is not an approximation and not a model choice -- it
%   is what the hardware does.
%
%   ================= WHY THIS EXISTS (Phase C1) =================
%   +physics/Constants.m has always derived R_unambiguous, and
%   +experiments/demoSwarmFlood.m caps its scenes at 2998 m and draws the
%   ring -- but nothing anywhere FOLDED a beyond-R_ua return.
%   cogengine/planner_cem.py's DEFAULT_BOUNDS_MULTI searched to 6000 m, so a
%   phantom planned at 5000 m was rendered at 5000 m, measured at 5000 m, and
%   scored at 5000 m, when at this radar's declared 50 kHz PRF it would
%   really have appeared at 2002.1 m. Planner and judge agreed only because
%   both were wrong in the same way.
%
%   ================= THE BIGGER PROBLEM THIS EXPOSED =================
%   Fixing the fold surfaced that this project's radar is internally
%   inconsistent, and has been throughout:
%
%       declared PRF 50 kHz  -> PRI  20 us =  64 samples -> R_ua   2998 m
%       receive window       ->      400 samples          -> spans 18737 m
%
%   The receive window is 6.25 PRIs long. A radar cannot listen for 125 us
%   between pulses it sends every 20 us. The window implies PRF = 8 kHz;
%   the declared PRF is 50 kHz; the project has quietly used whichever suited
%   the question:
%
%       for DOPPLER  it uses 50 kHz  -> unambiguous velocity +-375 m/s,
%                                       which covers the +-150 m/s envelope
%       for RANGE    it uses the window -> R_ua 18.7 km, which covers the
%                                       600-6000 m planner bounds
%
%   Both cannot be true. That is the classic range-Doppler ambiguity trade,
%   and this project has been escaping it by declaring two different PRFs for
%   two different purposes. See PHASE3_RESULTS.md C1 and
%   physics.assertPrfWindowConsistent below.

    C = physics.Constants();
    Rua = C.c / (2 * prfHz);
    ambigOrder = floor(rangeM ./ Rua);
    Rapp = rangeM - ambigOrder .* Rua;
end

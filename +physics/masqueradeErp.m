function M = masqueradeErp(varargin)
%MASQUERADEERP  The ERP a repeater must transmit to impersonate a real target.
%
%   M = physics.masqueradeErp('Name', value, ...)
%
%   Name-value
%       'TxErpW'        1e6    P_t*G_t, the radar's effective radiated power
%                              [W]. 1 kW into 30 dBi = 1e3 * 1e3 = 1e6 W.
%       'RcsM2'         1.0    sigma of the target being impersonated [m^2]
%       'JammerRangeM'  1800   R_d, where the DRONE actually is [m]
%       'ApparentRangeM' 2400  R_i, the range it wants to appear at [m]
%       'BudgetW'       200    peak transmit budget to report headroom against
%                              (cogengine/planner_cem.py's GAN_PEAK_POWER_W)
%
%   Returns
%       .required_erp_w   P_j*G_j
%       .required_erp_dbw, .required_erp_mw
%       .headroom_db      10*log10(BudgetW / required_erp_w)
%       .inputs
%
%   ================= THE ASYMMETRY THIS CAPTURES =================
%   A real echo makes a TWO-WAY trip and falls as 1/R^4 in power. A repeater
%   makes a ONE-WAY trip from wherever the drone physically is, so its
%   received power falls as 1/R_d^2 -- and R_d does not change just because
%   the phantom claims to be somewhere else. That mismatch IS the entire
%   1/R^2 amplitude screen in +track/discriminator.m: a phantom that
%   transmits at constant power while claiming to close from 2400 m to
%   1800 m shows a FLAT amplitude history, where a real closing target's
%   amplitude would have risen by (2400/1800)^2 = 1.78x.
%
%   To defeat that screen the repeater must vary its own ERP so the radar
%   receives exactly what a sigma-square-metre target at R_i would give:
%
%       received (real target at R_i)  = P_t*G_t*sigma / ((4pi)^2 * R_i^4)
%       received (repeater at R_d)     = P_j*G_j       / (4pi * R_d^2)
%
%   Setting them equal:
%
%       P_j*G_j = P_t*G_t * sigma * R_d^2 / (4pi * R_i^4)
%
%   VERIFIED (tests/test_masquerade_amplitude.m) at P_t*G_t = 1e6 W,
%   sigma = 1 m^2, R_d = 1800 m:
%       R_i = 2400 m -> 7.77 mW
%       R_i = 1800 m -> 24.6 mW
%
%   ================= AND THE POINT OF REPORTING HEADROOM =================
%   Those are MILLIWATTS against a 200 W budget: ~44 dB of headroom. EIRP
%   compliance has therefore never been a binding constraint on this
%   adversary, and that should be stated as a verified NON-constraint rather
%   than presented as a result. The phantom is not power-limited; it is
%   limited by what it knows and by what the geometry gives away.

    p = inputParser;
    addParameter(p, 'TxErpW',         1e6,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'RcsM2',          1.0,  @(x) isscalar(x) && x > 0);
    addParameter(p, 'JammerRangeM',   1800, @(x) isscalar(x) && x > 0);
    addParameter(p, 'ApparentRangeM', 2400, @(x) all(x > 0));
    addParameter(p, 'BudgetW',        200,  @(x) isscalar(x) && x > 0);
    parse(p, varargin{:});
    o = p.Results;

    Ri = o.ApparentRangeM;
    erp = (o.TxErpW * o.RcsM2 * o.JammerRangeM^2) ./ (4*pi * Ri.^4);

    M.required_erp_w   = erp;
    M.required_erp_mw  = erp * 1e3;
    M.required_erp_dbw = 10*log10(erp);
    M.headroom_db      = 10*log10(o.BudgetW ./ erp);
    M.inputs           = o;
end

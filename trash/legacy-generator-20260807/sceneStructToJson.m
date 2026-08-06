function jsonStr = sceneStructToJson(scene)
%SCENESTRUCTTOJSON  jsonencode(scene), guarding a real MATLAB jsonencode
%   quirk: a struct ARRAY of exactly one element collapses to a JSON OBJECT,
%   not a one-element JSON array -- but cogengine.schema.Scene.from_dict
%   always expects scene["phantoms"] to be a JSON array
%   (`[Phantom.from_dict(p) for p in d["phantoms"]]`), even for a
%   one-phantom scene.
%
%   Verified this breaks a real round-trip, not a hypothetical: a
%   one-phantom Scene struct (exactly what engine.decideScene returns for
%   this project's canonical scenes) serialized with plain jsonencode
%   produced Python error "ValueError: dictionary update sequence element #0
%   has length 1; 2 is required" -- Scene.from_dict iterated over the
%   phantom OBJECT's field-name keys as if each were a phantom dict.
%
%   jsonStr = engine.sceneStructToJson(scene)
%       scene : struct shaped like engine.sceneContract().scene, e.g. the
%               output of engine.decideScene -- use this (not raw
%               jsonencode) whenever handing a MATLAB Scene struct back to
%               cogengine.schema.Scene.from_json.

    if numel(scene.phantoms) == 1
        scene.phantoms = {scene.phantoms};
    end
    jsonStr = jsonencode(scene);
end

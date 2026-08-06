import { Config } from "@remotion/cli/config";

Config.setVideoImageFormat("jpeg");
Config.setConcurrency(4);
Config.setOverwriteOutput(true);
Config.setChromiumDisableWebSecurity(false);

// This film has no sound, but the rendered master carried an AAC track
// measuring -91 dB on both mean and max volume -- digital silence: bytes
// doing nothing, and a viewer who unmutes expecting narration finds none.
// The web copy in docs/assets was stripped with `-an` after the fact; this
// stops the master carrying it in the first place.
//
// setEnforceAudioTrack(false) is NOT enough, and was tried first. Remotion
// decides this in render-has-audio.js: `muted` returns "no" immediately,
// but with enforceAudioTrack merely false it still emits a track whenever
// the composition has any assets at all -- and every OffthreadVideo clip
// counts as one, whether or not that file has an audio stream. All eight of
// ours are video-only, and the flag made no difference to the output.
//
// Remove this if the film ever gains a soundtrack.
Config.setMuted(true);

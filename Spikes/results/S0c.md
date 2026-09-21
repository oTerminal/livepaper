## S0c: identity across two builds

Build 1 = 20260917132516. Signed selfsigned/plain, in /Applications.

```
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
[spike] login: status = enabled for /Applications/Livepaper.app
```

Build 2 = 20260917133517, source changed (window title), same certificate, replaced build 1 in /Applications.

```
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
[spike] login: status = enabled for /Applications/Livepaper.app
```

### Contrast: ad-hoc

```
[spike] login: status = notRegistered for /Applications/Livepaper.app
build 2 adhoc: # designated => cdhash H"3684488e3a3ad60b2ef5547944f89602a811e2d5"
[spike] login: status = enabled for /Applications/Livepaper.app
build 3 adhoc: # designated => cdhash H"d91783581c09bb802df8e694928fc066459b0690"
[spike] login: status = enabled for /Applications/Livepaper.app
```

The `login:` lines above are the output of `Livepaper login register|unregister|status` (they are also in
`raw/hazard-timeline.log`); the `notRegistered` line is the `unregister` between the two halves.

The logout half, reported by Vaibhav, 2026-09-17: "Works all the time. Register and unregister both work.
Ad-hoc also works." That is: after a logout the login item registered by build 1 launched build 2, for the
self-signed build and for the ad-hoc one. (Whether Login Items showed exactly one row was not reported
separately.) So on macOS 27 the login item follows the bundle, not the designated requirement, and an ad-hoc
build's changing code hash did not orphan it. The self-signed certificate is still what keeps the designated
requirement stable (above), which is what Gatekeeper and TCC key on.

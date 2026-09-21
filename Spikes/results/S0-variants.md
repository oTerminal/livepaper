### adhoc / deriveddata / plain / entitlements S0

Run 2026-09-17 13:32:07, macOS 27.0 (26A428).

```
variant: adhoc / plain / entitlements S0
CodeDirectory v=20400 size=876 flags=0x2(adhoc) hashes=21+3 location=embedded
Signature=adhoc
# designated => cdhash H"f19d5af7a9f9daa91bc2d7a6f736654dbb9ced2e"
CodeDirectory v=20400 size=1494 flags=0x2(adhoc) hashes=36+7 location=embedded
Signature=adhoc
# designated => cdhash H"54a4670db9210d424c386cabd3e13a8a8e61ccb6"
pluginkit:
app.livepaper.spike.extension(0.0.1)	545429C3-BDEE-454F-A091-6B4A1017A0DE	2026-09-17 12:31:49 +0000	<repo>/Spikes/build/DerivedData/Build/Products/
--- extension
2026-09-17 13:31:54.013 extension: INIT pid 40621 build 20260917132516 path <DerivedData>/Livepaper.app/Contents/Extensions/LivepaperExt
2026-09-17 13:31:54.013 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:31:54.035 extension: ACQUIRE new surface 3503D7A7-0076-44FF-A2A3-330085AE4E28 ctx 2935601689 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 40617 (1 surfaces)
2026-09-17 13:31:54.039 extension: ACQUIRE new surface 156F60FE-DCBC-485A-8F2A-0BADDBE6155D ctx 735235096 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 40617 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:31:53.990 I  amfid[373:9b19a] Entering OSX path for <app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:31:49.825 I  amfid[373:9b19a] Entering OSX path for <app>/Contents/MacOS/Livepaper
2026-09-17 13:31:53.991 Df amfid[373:9b19a] <app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certifi
2026-09-17 13:31:49.826 Df amfid[373:9b19a] <app>/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file://<app>/Contents/MacO
2026-09-17 13:31:49.824 Df kernel[0:9b450] (AppleMobileFileIntegrity) AMFI: '<app>/Contents/MacOS/Livepaper' is adhoc signed.
2026-09-17 13:31:53.990 Df kernel[0:9b5ab] (AppleMobileFileIntegrity) AMFI: '<app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension' is adhoc signed.
2026-09-17 13:31:53.991 Df kernel[0:9b5ab] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### adhoc / deriveddata / hardened / entitlements S0

Run 2026-09-17 13:32:33, macOS 27.0 (26A428).

```
variant: adhoc / hardened / entitlements S0
CodeDirectory v=20500 size=884 flags=0x10002(adhoc,runtime) hashes=21+3 location=embedded
Signature=adhoc
# designated => cdhash H"ef55e830ef5ed9d2b1b035c11b22745e627ae2f8"
CodeDirectory v=20500 size=1502 flags=0x10002(adhoc,runtime) hashes=36+7 location=embedded
Signature=adhoc
# designated => cdhash H"a70ac96722a7f5e81d0ee59d7ece02d2731f3181"
pluginkit:
app.livepaper.spike.extension(0.0.1)	CE2E0B78-B491-4685-BA68-A9635BF1FB4F	2026-09-17 12:32:15 +0000	<repo>/Spikes/build/DerivedData/Build/Products/
--- extension
2026-09-17 13:32:19.856 extension: INIT pid 41263 build 20260917132516 path <DerivedData>/Livepaper.app/Contents/Extensions/LivepaperExt
2026-09-17 13:32:19.857 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:32:19.878 extension: ACQUIRE new surface 1B713718-FF86-4E86-844D-E6049ED791C8 ctx 2487757406 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 41259 (1 surfaces)
2026-09-17 13:32:19.882 extension: ACQUIRE new surface 3B8EE424-640E-4977-BE43-90B9F1B123B3 ctx 2398047505 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 41259 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:32:19.833 I  amfid[373:9bb62] Entering OSX path for <app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:32:15.662 I  amfid[373:9bb62] Entering OSX path for <app>/Contents/MacOS/Livepaper
2026-09-17 13:32:19.834 Df amfid[373:9bb62] <app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certifi
2026-09-17 13:32:15.663 Df amfid[373:9bb62] <app>/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file://<app>/Contents/MacO
2026-09-17 13:32:15.662 Df kernel[0:9bdad] (AppleMobileFileIntegrity) AMFI: '<app>/Contents/MacOS/Livepaper' is adhoc signed.
2026-09-17 13:32:19.833 Df kernel[0:9beef] (AppleMobileFileIntegrity) AMFI: '<app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension' is adhoc signed.
2026-09-17 13:32:19.834 Df kernel[0:9beef] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### selfsigned / deriveddata / plain / entitlements S0

Run 2026-09-17 13:32:53, macOS 27.0 (26A428).

```
variant: selfsigned / plain / entitlements S0
CodeDirectory v=20400 size=876 flags=0x0(none) hashes=21+3 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
CodeDirectory v=20400 size=1494 flags=0x0(none) hashes=36+7 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
pluginkit:
app.livepaper.spike.extension(0.0.1)	69E45EE1-9D07-4AC1-9DB0-FFE40E821B2D	2026-09-17 12:32:34 +0000	<repo>/Spikes/build/DerivedData/Build/Products/
--- extension
2026-09-17 13:32:39.383 extension: INIT pid 41781 build 20260917132516 path <DerivedData>/Livepaper.app/Contents/Extensions/LivepaperExt
2026-09-17 13:32:39.384 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:32:39.405 extension: ACQUIRE new surface DBF8BA51-8FF0-4C2C-9521-8F042A23D880 ctx 4000068851 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 41777 (1 surfaces)
2026-09-17 13:32:39.414 extension: ACQUIRE new surface 58BE8BD0-1C86-4740-8178-8365B3BFBC45 ctx 355768071 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 41777 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:32:39.336 I  amfid[373:9c361] Entering OSX path for <app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:32:35.022 I  amfid[373:9c361] Entering OSX path for <app>/Contents/MacOS/Livepaper
2026-09-17 13:32:39.362 Df amfid[373:9c361] <app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certifi
2026-09-17 13:32:35.175 Df amfid[373:9c361] <app>/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file://<app>/Contents/MacO
2026-09-17 13:32:39.362 Df kernel[0:9c769] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### selfsigned / deriveddata / hardened / entitlements S0

Run 2026-09-17 13:33:12, macOS 27.0 (26A428).

```
variant: selfsigned / hardened / entitlements S0
CodeDirectory v=20500 size=884 flags=0x10000(runtime) hashes=21+3 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
CodeDirectory v=20500 size=1502 flags=0x10000(runtime) hashes=36+7 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
pluginkit:
app.livepaper.spike.extension(0.0.1)	203383FC-70B4-4FB3-B222-35B8F75A4ECF	2026-09-17 12:32:54 +0000	<repo>/Spikes/build/DerivedData/Build/Products/
--- extension
2026-09-17 13:32:58.809 extension: INIT pid 42377 build 20260917132516 path <DerivedData>/Livepaper.app/Contents/Extensions/LivepaperExt
2026-09-17 13:32:58.810 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:32:58.836 extension: ACQUIRE new surface 1A9387F1-756C-4298-ADCE-A04FA7455CD0 ctx 2271721383 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 42373 (1 surfaces)
2026-09-17 13:32:58.849 extension: ACQUIRE new surface 6B9862F5-3850-4725-82DF-D929AD8B5911 ctx 1368566769 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 42373 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:32:58.763 I  amfid[373:9cbb9] Entering OSX path for <app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:32:54.533 I  amfid[373:9cbb9] Entering OSX path for <app>/Contents/MacOS/Livepaper
2026-09-17 13:32:58.786 Df amfid[373:9cbb9] <app>/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certifi
2026-09-17 13:32:54.561 Df amfid[373:9cbb9] <app>/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file://<app>/Contents/MacO
2026-09-17 13:32:58.787 Df kernel[0:9cff6] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### adhoc / applications / plain / entitlements S0

Run 2026-09-17 13:33:31, macOS 27.0 (26A428).

```
variant: adhoc / plain / entitlements S0
CodeDirectory v=20400 size=876 flags=0x2(adhoc) hashes=21+3 location=embedded
Signature=adhoc
# designated => cdhash H"4d187d71f36949488873b535e227f5ab0bd4afee"
CodeDirectory v=20400 size=1494 flags=0x2(adhoc) hashes=36+7 location=embedded
Signature=adhoc
# designated => cdhash H"54a4670db9210d424c386cabd3e13a8a8e61ccb6"
pluginkit:
app.livepaper.spike.extension(0.0.1)	2092DB9D-1CAE-4DA3-8E89-CF842B4F71F3	2026-09-17 12:33:13 +0000	/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
--- extension
2026-09-17 13:33:18.130 extension: INIT pid 42940 build 20260917132516 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 13:33:18.130 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:33:18.150 extension: ACQUIRE new surface F6687420-3A6F-4483-A9AB-1C4C1B5DA065 ctx 1276703012 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 42934 (1 surfaces)
2026-09-17 13:33:18.162 extension: ACQUIRE new surface C4F1596B-851C-4667-B283-71D24E744D5A ctx 3658533345 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 42934 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:33:18.053 I  amfid[373:9d41d] Entering OSX path for /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:33:13.890 I  amfid[373:9d41d] Entering OSX path for /Applications/Livepaper.app/Contents/MacOS/Livepaper
2026-09-17 13:33:18.054 Df amfid[373:9d41d] /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed
2026-09-17 13:33:13.891 Df amfid[373:9d41d] /Applications/Livepaper.app/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file
2026-09-17 13:33:13.890 Df kernel[0:9d75b] (AppleMobileFileIntegrity) AMFI: '/Applications/Livepaper.app/Contents/MacOS/Livepaper' is adhoc signed.
2026-09-17 13:33:18.053 Df kernel[0:9d8fd] (AppleMobileFileIntegrity) AMFI: '/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension' is adhoc signed.
2026-09-17 13:33:18.054 Df kernel[0:9d8fd] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### adhoc / applications / hardened / entitlements S0

Run 2026-09-17 13:33:51, macOS 27.0 (26A428).

```
variant: adhoc / hardened / entitlements S0
CodeDirectory v=20500 size=884 flags=0x10002(adhoc,runtime) hashes=21+3 location=embedded
Signature=adhoc
# designated => cdhash H"f04372f8343634ac4a0271b7da2b29638d95b7c8"
CodeDirectory v=20500 size=1502 flags=0x10002(adhoc,runtime) hashes=36+7 location=embedded
Signature=adhoc
# designated => cdhash H"a70ac96722a7f5e81d0ee59d7ece02d2731f3181"
pluginkit:
app.livepaper.spike.extension(0.0.1)	FE6483CA-3683-4AC5-9EE7-A4AA46138503	2026-09-17 12:33:33 +0000	/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
--- extension
2026-09-17 13:33:37.460 extension: INIT pid 43407 build 20260917132516 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 13:33:37.461 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:33:37.483 extension: ACQUIRE new surface 8EE64CF9-5910-4F85-8CAF-A2D36B79B75F ctx 1901809943 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 43403 (1 surfaces)
2026-09-17 13:33:37.496 extension: ACQUIRE new surface 6F8F177C-BD83-4C77-8487-F3FE15C675BE ctx 3982699136 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 43403 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:33:37.440 I  amfid[373:9dce8] Entering OSX path for /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:33:33.233 I  amfid[373:9dce8] Entering OSX path for /Applications/Livepaper.app/Contents/MacOS/Livepaper
2026-09-17 13:33:37.440 Df amfid[373:9dce8] /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed
2026-09-17 13:33:33.234 Df amfid[373:9dce8] /Applications/Livepaper.app/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file
2026-09-17 13:33:33.233 Df kernel[0:9e07b] (AppleMobileFileIntegrity) AMFI: '/Applications/Livepaper.app/Contents/MacOS/Livepaper' is adhoc signed.
2026-09-17 13:33:37.440 Df kernel[0:9e12c] (AppleMobileFileIntegrity) AMFI: '/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension' is adhoc signed.
2026-09-17 13:33:37.440 Df kernel[0:9e12c] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### selfsigned / applications / plain / entitlements S0

Run 2026-09-17 13:34:10, macOS 27.0 (26A428).

```
variant: selfsigned / plain / entitlements S0
CodeDirectory v=20400 size=876 flags=0x0(none) hashes=21+3 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
CodeDirectory v=20400 size=1494 flags=0x0(none) hashes=36+7 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
pluginkit:
app.livepaper.spike.extension(0.0.1)	A285212A-B0C5-41F0-B199-8430EF377BC5	2026-09-17 12:33:52 +0000	/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
--- extension
2026-09-17 13:33:57.085 extension: INIT pid 44001 build 20260917132516 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 13:33:57.085 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:33:57.108 extension: ACQUIRE new surface 8B6BC681-D157-4B67-8F28-10127BAA7798 ctx 1475883174 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 43997 (1 surfaces)
2026-09-17 13:33:57.122 extension: ACQUIRE new surface F0119DBA-F138-4CEE-95BA-F5B7F6743FD2 ctx 744697746 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 43997 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:33:57.043 I  amfid[373:9e612] Entering OSX path for /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:33:52.725 I  amfid[373:9e612] Entering OSX path for /Applications/Livepaper.app/Contents/MacOS/Livepaper
2026-09-17 13:33:57.070 Df amfid[373:9e612] /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed
2026-09-17 13:33:52.857 Df amfid[373:9e612] /Applications/Livepaper.app/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file
2026-09-17 13:33:57.070 Df kernel[0:9ea71] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### selfsigned / applications / hardened / entitlements S0

Run 2026-09-17 13:34:30, macOS 27.0 (26A428).

```
variant: selfsigned / hardened / entitlements S0
CodeDirectory v=20500 size=884 flags=0x10000(runtime) hashes=21+3 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
CodeDirectory v=20500 size=1502 flags=0x10000(runtime) hashes=36+7 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
pluginkit:
app.livepaper.spike.extension(0.0.1)	814BD614-B5D2-4577-B540-73F3A8BDBF16	2026-09-17 12:34:12 +0000	/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
--- extension
2026-09-17 13:34:16.607 extension: INIT pid 44696 build 20260917132516 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 13:34:16.608 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:34:16.632 extension: ACQUIRE new surface 939EDC6B-5575-4788-8F1A-C8BCC1E76879 ctx 924025540 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 44692 (1 surfaces)
2026-09-17 13:34:16.648 extension: ACQUIRE new surface FC24B0D6-461F-4791-AF87-6B6665F939B9 ctx 1816063886 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 44692 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:34:16.558 I  amfid[373:9efe4] Entering OSX path for /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:34:12.323 I  amfid[373:9efe4] Entering OSX path for /Applications/Livepaper.app/Contents/MacOS/Livepaper
2026-09-17 13:34:16.591 Df amfid[373:9efe4] /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed
2026-09-17 13:34:12.361 Df amfid[373:9efe4] /Applications/Livepaper.app/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file
2026-09-17 13:34:16.591 Df kernel[0:9f473] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### selfsigned / applications / plain / entitlements S0 (after a rebuild)

Run 2026-09-17 13:35:41, macOS 27.0 (26A428).

```
variant: selfsigned / plain / entitlements S0
CodeDirectory v=20400 size=876 flags=0x0(none) hashes=21+3 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
CodeDirectory v=20400 size=1494 flags=0x0(none) hashes=36+7 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
pluginkit:
app.livepaper.spike.extension(0.0.1)	22DC0355-8DF0-4DCA-90C0-A7811C6B959A	2026-09-17 12:35:23 +0000	/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
--- extension
2026-09-17 13:35:27.743 extension: INIT pid 46835 build 20260917133517 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 13:35:27.744 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:35:27.769 extension: ACQUIRE new surface D0E56544-D3C4-4B2F-8346-E2C02E4CEE6A ctx 68936854 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 46768 (1 surfaces)
2026-09-17 13:35:27.784 extension: ACQUIRE new surface 4BD8A129-4B7E-44D7-99C9-9DF06D6498DA ctx 3811715506 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 46768 (2 surfaces)
2026-09-17 13:35:27.743 extension: INIT pid 46835 build 20260917133517 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 13:35:27.744 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:35:27.769 extension: ACQUIRE new surface D0E56544-D3C4-4B2F-8346-E2C02E4CEE6A ctx 68936854 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 46768 (1 surfaces)
2026-09-17 13:35:27.784 extension: ACQUIRE new surface 4BD8A129-4B7E-44D7-99C9-9DF06D6498DA ctx 3811715506 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 46768 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:35:27.688 I  amfid[373:a0940] Entering OSX path for /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:35:23.247 I  amfid[373:a0940] Entering OSX path for /Applications/Livepaper.app/Contents/MacOS/Livepaper
2026-09-17 13:35:27.718 Df amfid[373:a0940] /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed
2026-09-17 13:35:23.306 Df amfid[373:a0940] /Applications/Livepaper.app/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file
2026-09-17 13:35:27.719 Df kernel[0:a0da0] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### selfsigned / applications / plain / entitlements S1 (S1 entitlements)

Run 2026-09-17 13:37:15, macOS 27.0 (26A428).

```
variant: selfsigned / plain / entitlements S1
CodeDirectory v=20400 size=876 flags=0x0(none) hashes=21+3 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
CodeDirectory v=20400 size=1494 flags=0x0(none) hashes=36+7 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
pluginkit:
app.livepaper.spike.extension(0.0.1)	D617A136-6410-400B-839C-2167B0E9CEDA	2026-09-17 12:36:57 +0000	/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
--- extension
2026-09-17 13:37:01.695 extension: INIT pid 49702 build 20260917133555 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 13:37:01.696 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 13:37:01.728 extension: ACQUIRE new surface 527218A2-B76A-4EDD-8E08-90D1B34CEB37 ctx 3459967344 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 49698 (1 surfaces)
2026-09-17 13:37:01.744 extension: ACQUIRE new surface 79A91903-A035-409C-A666-5017C691C24D ctx 3195403246 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 49698 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 13:37:01.584 I  amfid[373:a2add] Entering OSX path for /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 13:36:57.183 I  amfid[373:a2add] Entering OSX path for /Applications/Livepaper.app/Contents/MacOS/Livepaper
2026-09-17 13:37:01.611 Df amfid[373:a2add] /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed
2026-09-17 13:36:57.325 Df amfid[373:a2add] /Applications/Livepaper.app/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file
2026-09-17 13:37:01.611 Df kernel[0:a2f97] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### selfsigned / applications / plain / entitlements S1 (engine fix build)

Run 2026-09-17 14:19:35, macOS 27.0 (26A428).

```
variant: selfsigned / plain / entitlements S1
CodeDirectory v=20400 size=940 flags=0x0(none) hashes=23+3 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
CodeDirectory v=20400 size=1590 flags=0x0(none) hashes=39+7 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
pluginkit:
app.livepaper.spike.extension(0.0.1)	8EFAAFF8-E7DB-4F3C-AA3B-9A82F2A6A689	2026-09-17 13:19:16 +0000	/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
--- extension
2026-09-17 14:19:21.232 extension: INIT pid 7993 build 20260917141846 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 14:19:21.233 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 14:19:21.255 extension: ACQUIRE new surface 124FE8EC-3916-4F34-8D81-6DAA3B418E03 ctx 956045046 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 7990 (1 surfaces)
2026-09-17 14:19:21.269 extension: ACQUIRE new surface 23AFB2E0-7650-46EC-8C06-552B536529E6 ctx 1277425280 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 7990 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 14:19:21.197 I  amfid[373:c927d] Entering OSX path for /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 14:19:16.851 I  amfid[373:c927d] Entering OSX path for /Applications/Livepaper.app/Contents/MacOS/Livepaper
2026-09-17 14:19:21.218 Df amfid[373:c927d] /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed
2026-09-17 14:19:17.002 Df amfid[373:c927d] /Applications/Livepaper.app/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file
2026-09-17 14:19:21.218 Df kernel[0:c974a] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### adhoc / applications / plain / entitlements S1 (ad-hoc with the S1 exception)

Run 2026-09-17 14:46:53, macOS 27.0 (26A428).

```
variant: adhoc / plain / entitlements S1
CodeDirectory v=20400 size=940 flags=0x2(adhoc) hashes=23+3 location=embedded
Signature=adhoc
# designated => cdhash H"caf755c48f4f14e1e3c9ce02a87e1b3484ec4c0f"
CodeDirectory v=20400 size=1590 flags=0x2(adhoc) hashes=39+7 location=embedded
Signature=adhoc
# designated => cdhash H"9da9ad3a0244eabb085b725b2fa300ce21e843c7"
pluginkit:
app.livepaper.spike.extension(0.0.1)	A79235F2-2451-4400-82E9-6DD2C0BDA14B	2026-09-17 13:46:35 +0000	/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
--- extension
2026-09-17 14:46:40.047 extension: INIT pid 70643 build 20260917144629 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 14:46:40.048 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 14:46:40.078 extension: ACQUIRE new surface 57FB0C0E-620A-41BC-BAE8-CDB5EEA529A9 ctx 65162639 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 70639 (1 surfaces)
2026-09-17 14:46:40.156 extension: ACQUIRE new surface FB40C9CD-FF99-484D-9E85-4A787E29CD2E ctx 4159395706 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 70639 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 14:46:40.033 I  amfid[373:eda8b] Entering OSX path for /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 14:46:35.842 I  amfid[373:eda8b] Entering OSX path for /Applications/Livepaper.app/Contents/MacOS/Livepaper
2026-09-17 14:46:40.034 Df amfid[373:eda8b] /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed
2026-09-17 14:46:35.844 Df amfid[373:eda8b] /Applications/Livepaper.app/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file
2026-09-17 14:46:35.842 Df kernel[0:edcd2] (AppleMobileFileIntegrity) AMFI: '/Applications/Livepaper.app/Contents/MacOS/Livepaper' is adhoc signed.
2026-09-17 14:46:40.033 Df kernel[0:edeff] (AppleMobileFileIntegrity) AMFI: '/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension' is adhoc signed.
2026-09-17 14:46:40.034 Df kernel[0:edeff] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.

### selfsigned / applications / plain / entitlements S1 (final engine build)

Run 2026-09-17 14:47:13, macOS 27.0 (26A428).

```
variant: selfsigned / plain / entitlements S1
CodeDirectory v=20400 size=940 flags=0x0(none) hashes=23+3 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
CodeDirectory v=20400 size=1590 flags=0x0(none) hashes=39+7 location=embedded
Authority=Livepaper Spike Self-Signed
designated => identifier "app.livepaper.spike.extension" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7"
pluginkit:
app.livepaper.spike.extension(0.0.1)	BE86292F-E1F7-43C9-ABDB-2886A7D9752B	2026-09-17 13:46:55 +0000	/Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
--- extension
2026-09-17 14:46:59.667 extension: INIT pid 71583 build 20260917144629 path /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex
2026-09-17 14:46:59.667 bridge: WallpaperExtensionKit loaded, all 15 payload classes present
2026-09-17 14:46:59.691 extension: ACQUIRE new surface C0BB210A-7DA0-46FC-AAD6-DCBEE0A3477B ctx 1721738322 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview false pid 71554 (1 surfaces)
2026-09-17 14:46:59.757 extension: ACQUIRE new surface 6B65C79C-D632-4CB6-9F1E-06C4472D0BB5 ctx 2146564588 display 1 37D8832A-2D66-02CA-B9F7-8F30A301B230 size 1800x1169@2.0 preview true pid 71554 (2 surfaces)
--- amfid / kernel / ExtensionKit
2026-09-17 14:46:55.336 I  amfid[373:eda8b] Entering OSX path for /Applications/Livepaper.app/Contents/MacOS/Livepaper
2026-09-17 14:46:59.629 I  amfid[373:ee8da] Entering OSX path for /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension
2026-09-17 14:46:55.482 Df amfid[373:eda8b] /Applications/Livepaper.app/Contents/MacOS/Livepaper not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed by an unknown certificate chain" UserInfo={NSURL=file
2026-09-17 14:46:59.653 Df amfid[373:ee8da] /Applications/Livepaper.app/Contents/Extensions/LivepaperExtension.appex/Contents/MacOS/LivepaperExtension not valid: Error Domain=AppleMobileFileIntegrityError Code=-423 "The file is adhoc signed or signed
2026-09-17 14:46:59.653 Df kernel[0:eeb17] (AppleMobileFileIntegrity) AMFI: [non-fatal] unable to accelerate context: app.livepaper.spike.extension | 65285
```
Result: extension launched and was acquired by WallpaperAgent.


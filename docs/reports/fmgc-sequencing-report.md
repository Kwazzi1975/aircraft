# FLYBYWIRE — TASK 01
# FMGS testing and visual debugging infrastructure

Repository: Kwazzi1975/aircraft
Branch inspected: master
Mode: read-only. No repository files were modified.

Verdict: FlyByWire does not have a working standalone visual FMGC sequencing test environment. Nothing in this repository runs the production LNAV sequencer and draws waypoint transitions outside Microsoft Flight Simulator. There is no startup command for such an application.

The sequencing algorithm itself is real TypeScript, shared by the A320 and the A380. It can be executed without the simulator once aircraft position is injected. No current test or UI does that.

Verified on this machine at 20:56 Asia/Oral (UTC+5), Vitest 3.0.8:

```
pnpm exec vitest run fbw-a32nx/src/systems/fmgc
```

Result: 8 files passed, 3 files skipped, 28 tests passed, 28 skipped. Git status stayed clean. Zero of those tests call LnavDriver, Geometry.shouldSequenceLeg, or BaseFlightPlan.sequence.

---

## 1. Executive summary

Automatic active-leg advancement lives in LnavDriver.update. Each MCDU frame (A320) or MFD frame (A380) calls GuidanceController.update, which calls that driver. The driver reads raw PLANE LATITUDE and PLANE LONGITUDE and advances BaseFlightPlan.activeLegIndex when geometry says the leg is finished.

The C++ module fbw-a32nx/src/wasm/fbw_a320/src/fmgc/Fmgc.cpp is the FMGC computer self-test (power, lights, discretes). It does not sequence flight-plan legs. A380 uses the same TypeScript sources: fbw-a380x/src/systems/tsconfig.json maps @fmgc/* to fbw-a32nx/src/systems/fmgc/src/*.

The decision is geometric:

- Distance-to-go under 0.001 NM along the inbound course.
- On a LATERAL_PATH guidance law, also inside 7 NM cross-track and 90 degrees track-angle error.
- Flight phase Takeoff or later (L:A32NX_FMGC_FLIGHT_PHASE >= 1).
- Inbound transition must not still be abeam, unless the leg is shorter than 0.01 NM or an XF leg has overshot.
- A null geometry leg sequences immediately and skips the phase and area gates.

There is no 5 NM sequencing or recovery radius in this code. The number 5 appears as an enroute minimum bank of 5 degrees (minBank) and as a 5 deg/s roll rate inside roll-anticipation distance. Turn anticipation can steer toward the next leg early. It does not change the active leg index. NAV versus HDG is not an input to the sequence test. When NAV is already engaged, a separate capture function uses a 30 NM zone (LnavDriver.NavActiveCaptureZone).

Vitest covers flight-plan editing only. The ND can draw the route inside MSFS. Its LNAV debug text overlay is compiled out of the render tree. Debug path points are not painted.

---

## 2. Inventory of existing tools

| Piece | Status | What it actually does |
|---|---|---|
| fbw-a32nx/src/systems/fmgc/src/flightplanning/**/*.spec.ts | Working | Plan edits, RPC, airways, waypoint parsing. No guidance loop. |
| NavigationDatabaseBackend.Test | Working, narrow | Airports CYYZ and CYVR, fixes NOSUS/DEBUS/DUTIL, airway A1. Departures, arrivals, and approaches return empty arrays. |
| ND CanvasMap | Sim-only | Draws flight-plan line and arc vectors inside MSFS. |
| LnavStatus | Present, not mounted | ND.tsx renders {false && <LnavStatus />}. |
| VnavStatus + VnavConfig | Sim-only, flags off | Text overlay is mounted. Messages publish only if DEBUG_GUIDANCE is turned on, through Coherent. |
| npm run serve:efb | Deprecated, incomplete | No index.html in the repo. Script port 9696. EFB README says port 10001. No FMGC sequencing. Not started here. |
| A380X ATCCOM/MultiFunctionDisplay.tsx | Abandoned prototype | new GuidanceController() with no arguments. Current constructor requires six. <FMS /> is not defined. Not registered in mach.config.js. |
| tools/fdr2csv | Offline | CSV of C++ FMGC structs from a flight recording. Not TypeScript leg sequencing. |
| tools/heapdump | Sim dump | JS object tree while MSFS is running. |
| WebUI-DevKit, ACE, SimBridge | External | Listed in fbw-a32nx/docs/resources.md. Not vendored. They do not host the sequencer by themselves. |
| fbw-a32nx/src/systems/fmgc/build.js | Broken entry | Bundles src/index.ts to html_ui/.../fmgc/fmgc.js. src/index.ts is absent. Instruments import @fmgc/* from source through Mach, so MCDU/MFD still compile the logic. The standalone fmgc.js build was not executed. |

No Storybook, Leaflet, Mapbox route viewer, nd-debug page, or in-repo navdata HTTP server was found.

---

## 3. Source paths and function names

### Call chain

Confirmed by repository search: the only callers of BaseFlightPlan.sequence() are LnavDriver.sequenceLeg and LnavDriver.trySequenceSecondaryPlan.

```
A32NX_FMCMainDisplay update
  -> GuidanceController.update(deltaTime)
    -> LnavDriver.update
      -> Geometry.shouldSequenceLeg(activeLegIdx, ppos)
      -> LnavDriver.sequenceLeg / sequenceDiscontinuity
        -> FlightPlanService.active.sequence()
          -> BaseFlightPlan.sequence()   // activeLegIndex++
```

A380 host: FlightManagementComputer calls this.guidanceController.update(dt) (around the update loop in fbw-a380x/src/systems/instruments/src/MFD/FMC/FlightManagementComputer.ts).

A320 host: fbw-a32nx/src/systems/instruments/src/MCDU/legacy/A32NX_FMCMainDisplay.ts calls this.guidanceController.update(deltaTime) when the controller exists.

### Files

| Role | Path | Symbols |
|---|---|---|
| Decision and actuation | fbw-a32nx/src/systems/fmgc/src/guidance/lnav/LnavDriver.ts | update, sequenceLeg, sequenceDiscontinuity, trySequenceSecondaryPlan, sequenceManual, disengageNavMode, computeNavCaptureCondition |
| Should-sequence geometry | fbw-a32nx/src/systems/fmgc/src/guidance/Geometry.ts | shouldSequenceLeg, getDistanceToGo, getGuidanceParameters, computeDistanceInDiscontinuity |
| Active index | fbw-a32nx/src/systems/fmgc/src/flightplanning/plans/BaseFlightPlan.ts | activeLegIndex (default 1), sequence, activeLeg |
| Orchestration | fbw-a32nx/src/systems/fmgc/src/guidance/GuidanceController.ts | constructor, init, update, activeLegIndex getter, automaticSequencing (written, never read by the driver) |
| Geometry build | fbw-a32nx/src/systems/fmgc/src/guidance/geometry/GeometryFactory.ts | createFromFlightPlan, geometryLegFromFlightPlanLeg |
| Along-track distance | fbw-a32nx/src/systems/fmgc/src/guidance/lnav/CommonGeometry.ts | courseToFixDistanceToGo, arcDistanceToGo, getRollAnticipationDistance, minBank |
| Course-to-fix leg | fbw-a32nx/src/systems/fmgc/src/guidance/lnav/legs/CF.ts | CFLeg.getDistanceToGo |
| Other legs | fbw-a32nx/src/systems/fmgc/src/guidance/lnav/legs/*.ts | TF, DF, FA, RF, AF, IF, CI, CR, FM, VM, HX (HM, HA, HF), PI, CA, CD, FC, FD |
| Phase enum | fbw-a32nx/src/systems/shared/src/flightphase.ts | FmgcFlightPhase |
| Phase writer | fbw-a32nx/src/systems/fmgc/src/flightphase/FlightPhaseManager.ts | changePhase writes L:A32NX_FMGC_FLIGHT_PHASE |
| Debug flags | fbw-a32nx/src/systems/fmgc/src/guidance/LnavConfig.ts | all debug flags false |
| VNAV debug flags | fbw-a32nx/src/systems/fmgc/src/guidance/vnav/VnavConfig.ts | DEBUG_GUIDANCE false, ALLOW_DEBUG_PARAMETER_INJECTION false |
| ND map | fbw-common/src/systems/instruments/src/ND/shared/map/CanvasMap.tsx | drawVector |
| ND LNAV text | fbw-common/src/systems/instruments/src/ND/shared/LnavStatus.tsx | listens for A32NX_FM_DEBUG_LNAV_STATUS |
| ND mount | fbw-common/src/systems/instruments/src/ND/ND.tsx | {false && <LnavStatus />}, {true && <VnavStatus />} |
| SimVar fast path | fbw-common/src/systems/shared/src/SimVarUtils.ts | RegisteredSimVar.get uses GetSimVarValueFastReg |
| Test SimVar mock | fbw-common/src/jest/setupJestMock.ts | GetSimVarValue / SetSimVarValue; GetRegisteredId returns 0; no FastReg |
| Vitest config | vitest.config.mjs | jsdom, setupJestMock.ts |
| CI | .github/workflows/pr-build-fs2024.yml | job test-js runs npm test |

### The sequence gate (LnavDriver.update)

```
const flightPhase = SimVar.GetSimVarValue('L:A32NX_FMGC_FLIGHT_PHASE', 'Enum');

const canSequence = !activeLeg.disableAutomaticSequencing && flightPhase >= FmgcFlightPhase.Takeoff;

let withinSequencingArea = true;
if (params.law === ControlLaw.LATERAL_PATH) {
  withinSequencingArea = Math.abs(params.crossTrackError) < 7 && Math.abs(params.trackAngleError) < 90;
}

if (
  (canSequence && withinSequencingArea && geometry.shouldSequenceLeg(activeLegIdx, this.ppos)) ||
  activeLeg.isNull
) {
  const nextLeg = geometry.legs.get(activeLegIdx + 1);
  const followingLeg = geometry.legs.get(activeLegIdx + 2);
  if (nextLeg) this.sequenceLeg(activeLeg, outboundTransition);
  else this.sequenceDiscontinuity(activeLeg, followingLeg);
}
```

Position is assigned just above that block:

```
// TODO FIXME: Use FM position
this.ppos.lat = LnavDriver.latitudeVar.get();    // PLANE LATITUDE
this.ppos.long = LnavDriver.longitudeVar.get();   // PLANE LONGITUDE
```

Registered vars in the same class: AIRSPEED TRUE, GPS GROUND SPEED, GPS GROUND TRUE TRACK.

### shouldSequenceLeg (Geometry.ts)

- No geometry leg at the index: return false. LnavDriver then returns early with "No leg at activeLegIdx" when DEBUG_GUIDANCE is on, and does not sequence.
- If the inbound transition exists, is not null, and isAbeam(ppos), and the leg distance is greater than 0.01 NM (unless the leg is an XF with overshot): return false.
- If activeLeg.isNull: return true.
- Else: dtg = activeLeg.getDistanceToGo(ppos); sequence when dtg is defined and dtg < 0.001.

### courseToFixDistanceToGo

Great-circle distance from present position to the fix, times the cosine of the angle between the bearing-to-fix and the inbound course, then Math.max(0, projection). Units are nautical miles.

Once the aircraft is at or past the fix along that course, distance-to-go stays 0, which already satisfies < 0.001 NM. The aircraft must also satisfy the 7 NM / 90 degree area when the active guidance law is LATERAL_PATH. Being 8 NM off the course line blocks sequencing even if the along-track projection is already 0.

### sequence() (BaseFlightPlan.ts)

- incrementVersion()
- If the active leg is the missed-approach point, stringMissedApproach()
- If the active leg has a cruise step, autoDeleteCruiseStep
- activeLegIndex++
- emit flightPlan.setActiveLegIndex

### sequenceDiscontinuity (LnavDriver.ts)

```
this.sequenceLeg(_leg, null);
this.disengageNavMode();          // isNavCaptureInhibited = true for 300 ms
if (followingLeg) this.sequenceLeg(null, null);
```

GeometryFactory skips elements with isDiscontinuity === true, so a discontinuity index has no geometry leg. If the next geometry slot is empty, this path runs. When a geometry leg exists two indexes ahead, the index advances twice: onto the discontinuity, then onto the leg after it. The same branch also runs at the end of the plan, where there is likewise no next geometry leg. In that case followingLeg is missing, so only one sequence() runs, plus the 300 ms NAV-capture inhibit.

geometryLegFromFlightPlanLeg throws if the leg after a discontinuity is neither IF nor CF:

```
[FMS/Geometry] Leg type after discontinuity can only be IF or CF
```

computeDistanceInDiscontinuity adds distance only when the next geometry leg is an IF and the previous leg has a path end (or a path start for VM/FM). Otherwise the discontinuity contributes 0.

VnavDriver.shouldShowLatDiscontinuityAhead is the lateral-discontinuity message. It requires FCU lateral mode NAV, skips holds that are not in immediate exit, skips vector legs, and returns true when predicted seconds to that leg are under 30 (or the TO-waypoint ETA is under 30 s if VNAV predictions are absent and that leg is active). It does not advance the leg.

### Leg behavior

| Leg | Sequencing behavior in this code |
|---|---|
| CF | courseToFixDistanceToGo. Allowed immediately after a discontinuity. Start point estimated if there is no inbound transition (CFLeg.estimateStartWithoutInboundTransition). |
| TF, DF, FA | Same along-track distance function. |
| RF, AF | arcDistanceToGo. Returns 0 once the swept angle is passed. |
| IF | getDistanceToGo returns undefined, so the distance test never passes. An xI-IF-xF triple sets geometryLeg.isNull = true, which sequences immediately. |
| CI, CR | Can set isNull when the intercept is invalid. That bypasses phase and area gates. CI getGuidanceParameters returns ControlLaw.TRACK, so the 7 NM gate is off. |
| FM, VM | disableAutomaticSequencing returns true. getDistanceToGo returns undefined. VM guidance law is HEADING. |
| HM | disableAutomaticSequencing is !termConditionMet. |
| HA | Same, and termConditionMet is set from INDICATED ALTITUDE >= target altitude. |
| HF | disableAutomaticSequencing returns false. Distance comes from the hold-entry transition. |
| CA | Course-capture inbound is special-cased in getGuidanceParameters so the CA leg stays the active guidable. Sequencing still uses the shared distance test. |

Default on Leg is disableAutomaticSequencing = false.

After a sequence, an outbound PathCaptureTransition or CourseCaptureTransition can force a left or right turn until absolute track-angle error is below GuidanceConstants.FORCED_TURN_TKAE_THRESHOLD (150 degrees).

### What is not a sequencing input

- Lateral mode NAV/HDG. Used by computeNavCaptureCondition and by the discontinuity-ahead message.
- ZULU TIME. Used by GuidanceController.formatLegEta for the TO-waypoint ETA. deltaTime is passed into update and is not used by the sequence predicate. The caller must move latitude and longitude.
- GuidanceController.automaticSequencing. Assigned true, including again later in the file, and never read by LnavDriver.
- LnavDriver.sequenceManual. Logs "[FMGC/Guidance] LNAV - sequencing MANUAL" and returns.
- LnavConfig.DEBUG_USE_SPEED_LVARS. Declared, no reader in the guidance tree.
- The 5 NM figure from older Fenix behavior. Not present as a sequencing distance in this tree.

### Roll anticipation (guidance switch, not an index change)

getRollAnticipationDistance(gs, bankA, bankB):

```
maxRollRate = 5 deg/s
k2 = 0.0038
rad = ((gs / 3600) * (sqrt(1 + (2 * k2 * 9.81 * deltaPhi) / maxRollRate) - 1)) / (k2 * 9.81)
```

Geometry.getGuidanceParameters uses the next guidable's phi command when rad > 0 and dtg <= rad, and the next law is LATERAL_PATH. activeLegIndex is unchanged.

### Flight phase enum

fbw-a32nx/src/systems/shared/src/flightphase.ts:

```
Preflight = 0
Takeoff = 1
Climb = 2
Cruise = 3
Descent = 4
Approach = 5
GoAround = 6
Done = 7
```

The comparison is >= Takeoff, so Preflight blocks sequencing and Done does not. FlightPhaseManager.changePhase writes L:A32NX_FMGC_FLIGHT_PHASE and also L:AIRLINER_FLIGHT_PHASE. The sequencer reads the LVar with SimVar.GetSimVarValue. GuidanceController separately subscribes to the fmgc_flight_phase event-bus topic for EFIS approach-message logic. Those two channels are not the same variable.

### Secondary flight plan

trySequenceSecondaryPlan sequences SEC n only when, before the active-plan increment is considered, the secondary FROM/TO pair matches what was just the active FROM/TO pair and the secondary activeLegIndex is one behind the active plan. Otherwise it leaves the secondary plan alone. With DEBUG_GUIDANCE it logs the mismatch.

---

## 4. Existing test commands

Runner: Vitest 3.0.8. Config: vitest.config.mjs. Environment: jsdom. Setup: fbw-common/src/jest/setupJestMock.ts. Root script: "test": "vitest run".

```
pnpm test
pnpm exec vitest run fbw-a32nx/src/systems/fmgc
pnpm exec vitest run fbw-a32nx/src/systems/fmgc/src/flightplanning/FlightPlanInterface.integration.spec.ts
pnpm exec vitest run fbw-a32nx/src/systems/fmgc/src/flightplanning/plans/FlightPlan.spec.ts
```

Executed in this environment (dependencies were already installed; nothing new was installed):

```
Test Files  8 passed | 3 skipped (11)
Tests       28 passed | 28 skipped (56)
```

Per file:

| File | Result |
|---|---|
| flightplanning/plans/FlightPlan.spec.ts | 13 tests, 11 skipped, 2 passed (insert leg, insert airway) |
| flightplanning/LegUtils.spec.ts | 4 passed |
| flightplanning/FlightPlanManager.spec.ts | 8 passed |
| flightplanning/FlightPlanInterface.integration.spec.ts | 8 passed |
| flightplanning/rpc/FlightPlanRpcClient.spec.ts | 2 passed |
| flightplanning/WaypointEntryUtils.spec.ts | 4 passed |
| flightplanning/FlightPlanService.spec.ts | 10 skipped (describe.skip) |
| flightplanning/segments/EnrouteSegment.spec.ts | 2 skipped (describe.skip) |
| flightplanning/plans/PendingAirways.spec.ts | describe.skip, 0 collected |
| flightplanning/segments/enroute/WaypointLoading.spec.ts | 2 skipped via skip() |
| flightplanning/uplink/SimBriefUplinkAdapter.spec.ts | 3 skipped via skip() |

There is no *.spec.ts under fbw-a32nx/src/systems/fmgc/src/guidance/. A380 FMGC tests do not exist. The only A380 spec found in the earlier survey is QnhUtils.spec.ts. No Rust or C++ test targets LnavDriver or BaseFlightPlan.sequence.

CI: .github/workflows/pr-build-fs2024.yml, job "Tests (JS)" / test-js. It runs ./scripts/dev-env/run.sh ./scripts/setup.sh --clean and then npm test. A search of .github/workflows found npm test only in that file. Rust tests are a separate job and do not cover this TypeScript sequencer.

Reusable fixtures, all under fbw-a32nx/src/systems/fmgc/src/flightplanning/test/:

| Export | File | Role |
|---|---|---|
| testEventBus | TestEventBus.ts | Real @microsoft/msfs-sdk EventBus |
| testFlightPlanService | TestFlightPlanService.ts | FlightPlanService(testEventBus, A320FlightPlanPerformanceData) |
| setupTestDatabase | Database.ts | NavigationDatabaseService.activeDatabase = Test backend |
| emptyFlightPlan | FlightPlan.ts | Empty FlightPlan |
| testFms | TestFms.ts | Partial FmsDisplayInterface for waypoint entry tests |
| assertDiscontinuity, assertNotDiscontinuity | LegUtils.ts | Type guards for plan elements |

Navdata fixture: fbw-common/src/systems/navdata/client/backends/Test/Test.ts and TestData.ts.

- FAKE_WAYPOINTS NOSUS, DEBUS, DUTIL are all at latitude 0, longitude 0.
- FAKE_AIRWAYS A1 chains those three fixes.
- TEST_AIRPORTS includes CYYZ (runway 06R has a real Toronto-area coordinate) and CYVR (airport location 0,0; its sample runway coordinate matches the CYYZ runway coordinate).
- getDepartures, getArrivals, getApproaches, getHolds return [].

The flight-plan tests therefore check editing and stringing. They cannot drive a geographically separated route through the production sequencer without new coordinates.

Global mock behavior that matters for any future sequencer test:

- SimVar.GetSimVarValue / SetSimVarValue use a map that beforeEach clears. Unknown names return 0.
- SimVar.GetRegisteredId returns 0 for every name.
- SimVar.GetSimVarValueFastReg is not defined.
- Coherent.call returns a Promise that never resolves.
- RegisterViewListener is a no-op object.
- Facilities.getMagVar returns 0.

RegisteredSimVar.get() calls SimVar.GetSimVarValueFastReg(this.id). LnavDriver latitude, longitude, ground speed, true track, and true airspeed all use RegisteredSimVar. The existing mock cannot feed those reads. Flight phase uses GetSimVarValue, so that one name can be stored with SetSimVarValue. No current FMGC spec does so.

---

## 5. Visual debugging capabilities

### Inside MSFS (real FMGC, real ND)

- A320 MCDU flight-plan page and A380 MFD F-PLN page show legs and DISCONTINUITY labels. They display state. They are not a headless harness.
- ND route rendering consumes EFIS symbols produced after GuidanceController.update (EfisSymbols on the MCDU/MFD side, ND subscribers on the display side).
- CanvasMap paints PathVectorType.Line (0) and PathVectorType.Arc (1). PathVectorType.DebugPoint falls through to default: break. LnavConfig.DEBUG_PREDICTED_PATH therefore adds points the ND does not draw.
- LnavConfig.DEBUG_GUIDANCE would publish a multiline status string on Coherent event A32NX_FM_DEBUG_LNAV_STATUS from Geometry.getGuidanceParameters. LnavStatus would render it. ND.tsx line with the overlay is {false && <LnavStatus />}, so the component is not mounted.
- VnavStatus is mounted. VnavDriver.updateDebugInformation returns immediately because VnavConfig.DEBUG_GUIDANCE is false. VnavConfig.ALLOW_DEBUG_PARAMETER_INJECTION is false. Its documented simvars are A32NX_FM_VNAV_DEBUG_POINT, _ALTITUDE, _SPEED, and _DISTANCE_TO_END. Those affect VNAV predictions, not the lateral sequence predicate.
- fbw-a32nx/docs/resources.md lists external WebUI-DevKit and Coherent devtools. Both assume the simulator.

### Not a visual sequencer

- serve:efb is the only in-repo browser UI script found. package.json places it under a "deprecated" banner: cd fbw-a32nx/src/systems/instruments/src/EFB/ && vite --port 9696. The EFB README says npm run serve:efb then http://localhost:10001. No index.html exists under the EFB tree. The EFB shows SimBrief route text and a progress bar from sim position. It does not run LnavDriver. It was not started.
- ATCCOM MultiFunctionDisplay.tsx intends to construct GuidanceController and EfisSymbols and tick them with useUpdate, and to render <FMS />. The current GuidanceController constructor requires (bus, fmgc, flightPlanService, efisInterfaces, efisNDRangeValues, acConfig). The current EfisSymbols constructor requires (bus, side, guidanceController, flightPlanService, navaidTuner, efisInterface, rangeValues, transmitVd). The file is not a Mach instrument. It does not build.
- tools/fdr2csv reads FDR recordings into CSV, including C++ FMGC struct fields. It does not execute TypeScript sequencing.
- tools/heapdump is a Python viewer for a sim heap dump.
- Mach watch rebuilds bundles to disk. It does not open a browser ND.

---

## 6. Dependency map for running the actual sequencer independently

| Need | Production source | Headless today |
|---|---|---|
| Flight plan and active index | FlightPlanService / BaseFlightPlan | Yes, via testFlightPlanService and emptyFlightPlan |
| Leg geometry | GeometryFactory.createFromFlightPlan | Yes if fixes have distinct coordinates. Test-backend enroute fixes do not. |
| Sequence decision | Geometry.shouldSequenceLeg | Pure function of geometry plus a LatLong. No SimVar. |
| Along-track distance | courseToFixDistanceToGo / arcDistanceToGo | Pure. |
| Index mutation | BaseFlightPlan.sequence | No position read. Emits an event on the plan's bus. |
| Full driver tick | LnavDriver.update | Blocked by RegisteredSimVar until the mock grows GetSimVarValueFastReg and unique registration ids. |
| Latitude / longitude | PLANE LATITUDE, PLANE LONGITUDE via RegisteredSimVar | Not stubbed |
| Ground speed | GPS GROUND SPEED via RegisteredSimVar | Feeds guidance parameters and roll anticipation, not the 0.001 NM comparison itself |
| True track | GPS GROUND TRUE TRACK via RegisteredSimVar | Becomes track-angle error on LATERAL_PATH |
| True airspeed | AIRSPEED TRUE via RegisteredSimVar | Bank limits and roll-anticipation distance |
| Flight phase | L:A32NX_FMGC_FLIGHT_PHASE via GetSimVarValue | Mock can store it. Must be >= 1 or canSequence is false. |
| Lateral mode | L:A32NX_FMA_LATERAL_MODE and FMGC discrete word 2 bit 12 | Capture condition and the disco message. Not the sequence gate. |
| Discontinuity | FlightPlanElement.isDiscontinuity | Insert through the flight-plan API, or a plan element with isDiscontinuity true. Geometry skips that index. |
| Leg type CF after disco | GeometryFactory | Legal. Other types after a disco throw. |
| Time | deltaTime argument; ZULU TIME for ETA | Not an input to the predicate. Move lat/lon between ticks. |
| Event bus | SDK EventBus | Sequencing does not wait on a bus message. The sequence event is an output. |
| Nav database | Test backend or a hand-built Fix passed into CFLeg/TFLeg | Hand-built legs avoid the colocated fixture. |
| WASM, Coherent GT, MSFS panel | Not used by the TypeScript predicate | RegisterViewListener is a no-op in Vitest. Coherent.call never resolves, so RegisteredSimVar.set would hang if invoked. |
| GuidanceController.update as a whole | Also runs VNAV, pseudo-waypoints, EFIS simvar writes | Heavier than LnavDriver.update. Needs an Fmgc stub (weights, speeds, elevations) and EFIS interfaces. |

Smallest production entry that still is the real algorithm: build geometry, then either call Geometry.shouldSequenceLeg directly, or call LnavDriver.update after the SimVar fast-path mock exists. Do not reimplement courseToFixDistanceToGo.

---

## 7. Verified functionality versus limitations

Verified by reading the sources, and for the suite by running Vitest:

- Sequencing is the TypeScript path in section 3. One implementation serves A320 and A380.
- Thresholds are 0.001 NM, 7 NM cross-track, 90 degrees track error, phase >= Takeoff, and the inbound-transition exception.
- Null legs bypass those gates.
- Discontinuities are skipped in geometry and crossed by a double sequence plus a 300 ms NAV-capture inhibit.
- No guidance spec exists. The flight-plan suite result is 28 passed and 28 skipped.
- ND LNAV debug text is not mounted. Debug path points are not drawn.
- The Vitest SimVar mock cannot feed RegisteredSimVar.
- src/index.ts for the legacy fmgc bundle is absent.
- EFB has no index.html. ATCCOM does not match current constructors and is not a Mach instrument.
- Repository git status was clean after the test run.

Not executed, so not claimed as a runtime result:

- pnpm run build-a32nx:fmgc
- npm run serve:efb
- a Mach ND or MCDU build
- a headless LnavDriver.update call
- Microsoft Flight Simulator

The missing index.ts, missing EFB index.html, constructor mismatch, and FastReg gap are file facts. They are not a claim that those commands were run.

---

## 8. Recommended testing workflow without MSFS

What works today, with no code changes:

```
pnpm exec vitest run fbw-a32nx/src/systems/fmgc
```

Use this for flight-plan structure: inserts, discontinuities created by edits, airways on the test backend, and the RPC boundary. It does not move an aircraft and it does not advance the active leg because of position.

There is no command that visually sequences waypoints outside MSFS.

For active-leg transitions as the aircraft is shipped, the host is MSFS: MCDU on the A320 or MFD on the A380 constructs GuidanceController, and the ND displays EFIS symbols. In-sim HTML debugging is the external WebUI devkit and Coherent devtools named in fbw-a32nx/docs/resources.md. LnavConfig and VnavConfig debug flags are source constants set to false, so an overlay still requires a source edit plus the simulator.

Until a sequencer spec exists, treat any off-sim story about a 5 NM recovery as unrelated to this code. The production test is the 0.001 NM along-track predicate plus the 7 NM cross-track gate on LATERAL_PATH.

---

## 9. Minimum implementation plan (not implemented)

Do not replace the algorithm. Call it.

1. Extend fbw-common/src/jest/setupJestMock.ts so GetRegisteredId returns a stable id per variable name, and GetSimVarValueFastReg plus setValueReg_Number read and write the same map as GetSimVarValue. Without this, LnavDriver.update cannot see injected latitude, longitude, ground speed, or track.

2. Add a Vitest next to the guidance sources that:
   - builds TF and CF legs with distinct coordinates (do not use NOSUS/DEBUS/DUTIL; they share 0,0)
   - builds geometry with GeometryFactory or by placing those legs in a Geometry map at flight-plan indexes
   - sets L:A32NX_FMGC_FLIGHT_PHASE to Takeoff or later through the mock
   - steps present position along the inbound course
   - asserts activeLegIndex increments only when distance-to-go is under 0.001 NM, and that LATERAL_PATH sequencing waits while absolute cross-track error is 7 NM or more
   - asserts a discontinuity produces two sequence() calls and that a non-IF/non-CF leg after a discontinuity is rejected by GeometryFactory
   - asserts FM/VM and an unmet HM do not auto-sequence, and that a null leg sequences even in Preflight

3. For a picture, plot the legs' existing PathVector lines and arcs and the injected position, and print active index, ident, and distance-to-go each tick. Keep courseToFixDistanceToGo and shouldSequenceLeg as the decision. Mounting CanvasMap means pulling in the ND instrument, its publishers, and Coherent, and it still drops DebugPoint vectors. A small plot of PathVector plus ppos is the smaller visual layer.

No such test or plot exists in the repository today.

---

## Confirmed versus inference

Confirmed:

- File paths, function names, numeric thresholds, and the call chain above.
- Vitest counts from an actual run.
- Absence of a browser sequencer, of guidance specs, of fmgc/src/index.ts, and of an EFB index.html.
- RegisteredSimVar versus the Jest mock, by reading both implementations.

Inference, not a runtime result:

- pnpm run build-a32nx:fmgc fails because its input file is missing.
- npm run serve:efb cannot open a page because index.html is missing.
- ATCCOM MultiFunctionDisplay does not typecheck against the current GuidanceController and EfisSymbols constructors.
- Calling LnavDriver.update under the current Vitest mock throws or reads undefined on GetSimVarValueFastReg. That call was not added or executed.

---

## Bottom line

FlyByWire already has the production sequencer: LnavDriver.update in fbw-a32nx/src/systems/fmgc/src/guidance/lnav/LnavDriver.ts, driven by GuidanceController inside the MCDU (A320) and the MFD FMC (A380).

FlyByWire does not have a working standalone visual FMGC sequencing test environment. There is no command to start one, no page to open, and no fixture that both loads a separated flight plan and shows FROM/TO transitions. The closest automated tool is:

```
pnpm exec vitest run fbw-a32nx/src/systems/fmgc
```

That command checks flight-plan editing only.

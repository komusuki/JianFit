# JianFit

**Your AI form coach, Coach Zhang.** Only clean reps count.

A camera-based Android app that coaches home bodyweight exercise form in real time. It watches you through the phone's front camera, counts **only correct reps**, and speaks short corrections like "Go lower" or "Keep your hips up" when your form slips. Everything runs on the phone, so it works offline and no video ever leaves the device.

Built by a 3-person team in 3 weeks, following the **Version 2 (Focused)** roadmap.

## Scope (Version 2)

**Core exercises (8):** bodyweight squat, jump squat, knee push-up, standard push-up, forward lunge, reverse lunge, forearm plank, glute bridge.

**If ahead of schedule (2):** decline push-up, good morning.

**Main features**
- Live skeleton overlay with red and green joint highlights
- Correct-only rep counting, with attempted reps shown separately
- Spoken form cues, with a limit on how often each cue repeats
- Strictness levels: Beginner, Standard, Strict
- Single Exercise Mode: pick an exercise, reps and sets, with a rest timer
- Custom Workout Mode: build and run a routine of several exercises
- Session summary and workout history, saved on the phone
- Camera setup guide for each exercise

**Should have, if time allows:** too-many-reps warning, fatigue warning after 3 failed reps in a row, rule-based wrong-exercise check, rest and hydration messages.

## Tech stack

All tools are free.

**App (Android only)**
- Flutter and Dart
- `google_mlkit_pose_detection`: on-device pose detection (33 body points)
- `camera`: live camera stream
- `flutter_tts`: spoken cues
- `sqflite` and `path`: local database for sessions and reps
- `shared_preferences`: settings
- `wakelock_plus`: keeps the screen on during workouts
- `permission_handler`: camera permission

**Tuning tools (Python, in `tools/`)**
- MediaPipe, OpenCV, NumPy, pandas, matplotlib, Jupyter

**Team tools**
- GitHub (code), Google Drive (test videos, private), Notion (task tracker)

## How it works

1. **Pose detection:** ML Kit finds 33 body points in each camera frame.
2. **Measurements:** the engine turns those points into joint angles, body line and lean, smoothed over 3 to 5 frames. Joints with low confidence are ignored.
3. **Rep counter:** a state machine (Ready, Going Down, Bottom, Coming Up, Complete) with two thresholds and a gap between them, so shaky movement doesn't double-count.
4. **Form judge:** checks depth, cleanliness (based on the strictness level) and fixed safety rules for each rep.
5. **Cue manager:** picks the most important mistake and speaks one short cue.
6. **Storage:** saves every rep and its failed checks to SQLite.

Exercises are data, not code. Each exercise is one JSON file in `assets/exercises/` with its joints, thresholds, checks and cues.

## Folder structure

```
lib/
  engine/      measurement layer, rep counter, form judge, cue manager
  screens/     app screens
  widgets/     reusable UI pieces, including the skeleton painter
  services/    camera, pose detection, text-to-speech, database
  models/      data classes (exercise, rep, session)
  main.dart
assets/
  exercises/   one JSON file per exercise
  replay/      CSV files of body points for replay mode
tools/         Python replay and tuning tools (built by Member C, used by everyone)
```

## Setup

1. **All 3 members** install Git, Android Studio (with the Android SDK, Command-line Tools and Platform-Tools), the Flutter SDK, and Python with the tuning packages. Everyone writes Dart code and tunes their own exercises.
2. **Flutter version for this project: `3.47.9` (stable, Dart 3.13.7).** Everyone must use exactly this version. Check yours with `flutter --version`.
3. Install the Flutter and Dart plugins in Android Studio, then run `flutter doctor` until it shows no issues.
   - Keep the Flutter SDK and the Android SDK in paths **without spaces** (for example `C:\dev\IntroAI\flutter` and `C:\dev\Android\Sdk`). If your Windows username has a space, don't use your Documents or AppData folders.
4. Clone the repository, then run:
   ```
   flutter pub get
   flutter run
   ```
5. Create an Android emulator in Android Studio (Device Manager) and set its front camera to your webcam. Use it for daily work.
6. Live camera checks run on the team's shared phone (see Devices below).

## Devices

The team has one Android phone, a **Huawei Nova 5T**, and meets at school on most weekdays. A second phone is borrowed for the pilot.

- **Emulator for daily work:** screens, navigation, workout flows, the database, history and summaries, all with fake data and hot reload.
- **Replay mode (from Day 7):** a hidden Settings switch (Camera or Replay) makes the app read saved body points from a CSV instead of the camera, so rep counting, cues and Single Exercise Mode can be tested on the emulator.
- **The phone is only for:**
  - live pose tracking and confirming tuned exercises
  - frames per second and cue delay
  - running a routine hands-free
  - the release APK and the pilot
- **Phone schedule:**
  - Days 1 to 9: Member A has priority, since the camera and engine are the critical path.
  - From Day 10: a daily slot at school after the check-in, about 30 minutes per member who needs it.
  - Joint sessions: Day 7, Day 11, Day 12, Day 13, Day 14, Day 17, and Days 18 to 19.
- **Testing without a cable:** build a debug APK with `flutter build apk --debug`, upload it to the team Drive, and the phone owner installs it.
- **Huawei setup:**
  - Turn on USB debugging and **Allow ADB debugging in charge only mode**.
  - Install Huawei HiSuite if Windows doesn't detect the phone.
  - Android 10 has no Wireless debugging, so to go cable-free, connect by USB once and run:
    ```
    adb tcpip 5555
    adb connect PHONE_IP:5555
    ```
- **Protect the phone:** keep it charged and in a case. Upload videos to the Drive the same day.

## Team roles

Data and testing work (recording, labeling, tuning, confirming exercises, and the pilot) is shared evenly by all 3 members. Each member owns a set of exercises from recording all the way to confirming it on the phone.

- **Member A: Engine and AI** (GitHub: @______)
  Camera and ML Kit connection, measurement layer and shared formula document, rep counter, exercise JSON format, form judge, cue manager, and performance. Reviews every engine change and exercise JSON file.
- **Member B: App and Interface** (GitHub: @______)
  Project and repository setup, all screens and navigation, Single and Custom Workout Modes, rest screen, rest and hydration messages, onboarding and safety reminder, the SUS survey, and the release APK.
- **Member C: Data Tools and Storage** (GitHub: @______)
  Consent form, private video folder, labeling spreadsheet, the Python replay tool, database, session summary, history, should-have warnings and the rule-based exercise check, engine tests, the 30-minute and airplane mode test, and combining pilot results.

### Shared data and testing work

**Exercise ownership.** Each owner records, labels, tunes, writes the JSON file, and confirms it on the phone with Member A.
- Member A: bodyweight squat, jump squat, forearm plank
- Member B: knee push-up, standard push-up, glute bridge
- Member C: forward lunge, reverse lunge, plus decline push-up and good morning if ahead

**Recording sessions.** All 3 members are subjects, and each owner directs their own exercises.
- Day 4: squat, push-up, and lunge pairs
- Day 10: forearm plank, glute bridge, decline push-up, good morning

Member C runs every video through the replay tool and shares the plots with each owner.

**Pilot.** Each member recruits 2 testers (about 6 in total), collects their consent forms, and runs their sessions with the shared script. Member C combines everyone's results.

**Success targets.**
- Member A: frames per second and cue delay
- Member B: SUS score
- Member C: rep accuracy, form agreement, and the crash and airplane mode test

**Write-up.** Each member writes the section on their own work.

## Team routine

- **Start of day:** `git pull` on `main`, then run the app on your emulator (or the Nova 5T if you have it) before writing new code.
- **Daily 15-minute check-in:** what you finished, what you're doing next, and what's blocking you.
- **During the day:** small commits, and a quick test of whatever you built: emulator or replay mode for screens and logic, the Nova 5T for live camera features.
- **End of day:** commit, push your branch, and update your tasks in the Notion tracker.
- **Recording sessions:** Day 4 and Day 10, about 2 to 3 hours each, with everyone present.
- **Checkpoints:**
  - Day 4: skeleton working on the phone. If not, Member B joins Member A until it is.
  - Day 9: Single Exercise Mode works with the squat. If not, Custom Workout Mode becomes one preset routine.
  - Day 14: all 8 exercises confirmed on the phone. If not, cut in this order: reverse lunge, jump squat, glute bridge.
  - Day 17: feature freeze. After this, bug fixes only.
  - Days 18 to 19: pilot test, together at school on the Nova 5T and the borrowed phone.
  - Day 21: delivery.

## Team rules

**Branches and pull requests**
- Never push directly to `main`. `main` must always run.
- One branch per tracker subtask, named with your role letter: `a/rep-counter`, `b/settings-screen`, `c/replay-tool`.
- After the feature freeze, use fix branches only: `fix/cue-delay`.
- Keep branches small. Merge within 1 to 2 days.
- Every pull request needs one approval. Member A reviews engine and exercise JSON changes. Anyone can review screen changes.
- Only merge code you've tested: on the emulator or in replay mode for screens and logic, and on the Nova 5T for anything that uses the live camera.
- Merge `main` into your branch daily if your task takes more than a day.

**Files**
- Stay in your own folders where you can: A in `lib/engine/`, B in `lib/screens/` and `lib/widgets/`, C in `lib/services/` (database) and `tools/`.
- Each owner writes the JSON files for their own exercises in `assets/exercises/`. Member A reviews every one before it's merged.
- If one owner falls behind on tuning, the member furthest ahead takes over that exercise at the next check-in.
- Announce in the check-in before adding a package to `pubspec.yaml`.
- Never commit videos, personal data, or API keys. Test videos go in the private Google Drive folder.

**Data and safety**
- Everyone who appears in a test video or the pilot signs a consent form first.
- The app gives form feedback only. It isn't medical advice, and the app shows a safety reminder before workouts.

## Success targets

- Rep counting accuracy of at least 95%
- Form judgment agreement of at least 85% with a human reviewer
- At least 15 frames per second on the Nova 5T and the borrowed phone
- Spoken cue within about 1 second of the mistake
- A System Usability Scale (SUS) score from pilot testers
- No crashes in a 30-minute session, and works fully in airplane mode

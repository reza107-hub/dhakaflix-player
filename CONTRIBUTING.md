# Contributing

Thanks for helping! Keep changes small and focused.

- **Bugs and ideas:** open an issue using a template. For playback problems,
  include the file name (or folder) on DhakaFlix, your device, and the app
  version (Settings → About).
- **Code:** fork, make a branch, and open a pull request. Before you push:

  ```sh
  flutter analyze
  flutter test --exclude-tags live      # unit tests, no network needed
  flutter test --tags live              # needs the DhakaFlix network
  ```

- Keep the app **read-only** towards DhakaFlix: only GET (with Range),
  folder listings and search. Never add upload, delete or rename calls.
- No analytics, tracking or accounts.
- By contributing you agree that your work is licensed under GPL-3.0.

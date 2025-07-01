# Virgo Project `GEMINI.md`

This file provides project-specific guidance for the Gemini agent.

## Project Overview

Virgo is a SwiftUI-based application for iOS and macOS that helps users practice and play along with drum tracks. The app features a browsable and searchable library of drum tracks, each with properties like title, artist, BPM, genre, and difficulty.

The core technologies used are:

- **SwiftUI:** For building the user interface across all Apple platforms.
- **SwiftData:** For persisting drum track data locally on the device.

## File Structure

The project follows a standard Xcode project structure:

- **`Virgo/`**: Contains the main application source code.
  - **`VirgoApp.swift`**: The main entry point of the application.
  - **`MainMenuView.swift`**: The root view of the app, containing the tab bar and navigation.
  - **`ContentView.swift`**: The primary view for displaying and interacting with the list of drum tracks.
  - **`DrumTrack.swift`**: The SwiftData model for the drum tracks.
  - **`Assets.xcassets`**: Contains app icons, colors, and other assets.
- **`Virgo.xcodeproj/`**: The Xcode project file.
- **`VirgoTests/`**: Unit tests for the application.
- **`VirgoUITests/`**: UI tests for the application.

## Development Conventions

When making changes to the Virgo project, please adhere to the following conventions:

### Code Style

- **SwiftUI Best Practices:** Use SwiftUI's declarative syntax and view composition to build the UI. Keep views small and focused on a single responsibility.
- **SwiftData:** Use the `@Model` macro to define data models and the `@Query` property wrapper to fetch data. All data-related logic should be encapsulated within the `DrumTrack` model or a dedicated service class.
- **Naming Conventions:** Follow Swift's naming conventions (e.g., `camelCase` for properties and methods, `PascalCase` for types).

### Commits

- **Commit Messages:** Write clear and concise commit messages that describe the changes made. Use the imperative mood (e.g., "Add feature" instead of "Added feature").
- **Atomic Commits:** Each commit should represent a single logical change. Avoid bundling unrelated changes into a single commit.

### Testing

- **Unit Tests:** Add unit tests for new models, views, and business logic in the `VirgoTests` target.
- **UI Tests:** Add UI tests for new user flows and interactions in the `VirgoUITests` target.

## How to Run the App

To run the Virgo app, open `Virgo.xcodeproj` in Xcode and run the "Virgo" scheme on the desired simulator or device.

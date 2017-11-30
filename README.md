# light-playground

An interactive 2D raytracer for iOS, written in Swift.

![Screenshot](Screenshot.png)

Inspired by the awesome [Zen photon garden](https://github.com/scanlime/zenphoton)

## Architecture Highlights
*Note: This will likely change in the near future*

### MainViewController
This is the entry point of the app, and is considered the UI level. Contains a single `LightSimulator`.

### LightSimulator
Is the primary way the UI interacts with the simulation. Is responsible is enqueing and managing concurrent `Tracers`, clearing or re-creating the `LightGrid`, and notifying the UI when a new image is ready to be shown to the user.

### Tracer
A `Tracer` is a operation which, given a scene layout, traces some number of rays and draws them onto a `LightGrid`. Multiple tracers may be running at once and each one locks the `LightGrid` when drawing to prevent conflicts.

### LightGrid
A `LightGrid` is a surface to draw light segments on. Drawing using both the CPU and Metal is currently supported.

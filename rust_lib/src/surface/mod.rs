pub mod cpu;


/// After some `LightSegment`s are produced, they are drawn using a `Surface`. Surfaces must
/// be thread-safe (they will be called from `Tracer`s on multiple threads), and they can be
/// implemented using anything which supports drawing (CPU, OpenGL, Metal, etc.).
///
/// For some flexibility, drawing is done by first acquiring a session, performing the draw, and
/// finally committing. This allows us to play with different behaviors, like drawing to buffers
/// and only locking on commit.
pub trait Surface: Sync + Send {
    type SurfaceSessionType: SurfaceSession;

    fn draw_session() -> Self::SurfaceSessionType;
}

/// Manages a single drawing session from a single thread.
pub trait SurfaceSession {}

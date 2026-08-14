// Release builds with Firebase web configuration replace this no-op file with
// a pinned SDK preloader. Demo and local builds stay network-independent.
window.firebaseSdkReady = Promise.resolve();

#ifndef TVS_NODE_PROCESS_BRIDGE_H_
#define TVS_NODE_PROCESS_BRIDGE_H_

#include <string>

#include <windows.h>

#include "flutter_window.h"

/// Spawns the embedded/system Node.js runtime as a child process and
/// watches the TVS startup-ack handshake file (node-main-template.js
/// protocol: writes .startup.ack with {status:"ok"} when the CatVod
/// spider HTTP server is listening).
class NodeProcessBridge {
 public:
  NodeProcessBridge(const FlutterWindow& window,
                    const std::wstring& nodePath,
                    const std::wstring& bundlePath,
                    int port, int dartPort);
  ~NodeProcessBridge();

  // Start the node child process; blocks until the ack file signals
  // the server is up or the 45s timeout elapses.
  void Start();

  // Terminate the child process (also called on window close).
  void Stop();

  int port() const { return port_; }

 private:
  const FlutterWindow& window_;
  std::wstring nodePath_;
  std::wstring bundlePath_;
  int port_;
  int dartPort_;

  HANDLE process_ = nullptr;
  HANDLE thread_ = nullptr;
  bool running_ = false;
};

#endif  // TVS_NODE_PROCESS_BRIDGE_H_

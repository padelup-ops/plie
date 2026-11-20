// WebAudioCapture.swift — Foldboard
//
// Adapted from stephancill/ios-keyboard-dictation (MIT License, Copyright (c) 2026 Stephan Cilliers):
// https://github.com/stephancill/ios-keyboard-dictation
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
// documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice
// and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
//
// La dictée dans le clavier, sans passer par l'app : WebKit tient le micro dans ses propres processus (getUserMedia),
// le clavier reçoit le son en 16 kHz. Une page cachée, un battement de cœur : si le clavier disparaît, le micro se coupe.

import UIKit
import WebKit

/// Captures microphone audio from inside a keyboard extension by running `getUserMedia`
/// in a hidden `WKWebView`. WebKit performs the capture in its own processes, which avoids
/// the keyboard-process audio restrictions that break `AVAudioEngine` / `AudioQueue`.
///
/// Emits 16 kHz mono Int16 PCM chunks through `onAudio`.
@MainActor
final class WebAudioCapture: NSObject {
    static let sampleRate: Double = 16_000

    var onReady: (() -> Void)?
    var onStarted: (() -> Void)?
    var onAudio: ((Data, Float) -> Void)?
    var onEnded: ((String) -> Void)?

    private(set) var isReady = false
    private(set) var isCapturing = false
    private let webView: WKWebView
    private var heartbeat: Timer?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakMessageHandler(self), name: "capture")
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
    }

    /// The web view must live in the keyboard's view hierarchy for WebKit to capture.
    func attach(to view: UIView) {
        view.addSubview(webView)
        view.sendSubviewToBack(webView)
        // https base URL gives the page a secure context, which getUserMedia requires.
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://foldboard-dictation.invalid/"))
    }

    func start() {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.webView.evaluateJavaScript("captureHeartbeat()") }
        }
        webView.evaluateJavaScript("startCapture(); 0") { [weak self] _, error in
            if let error { Task { @MainActor in self?.finish(reason: "start failed: \(error.localizedDescription)") } }
        }
    }

    func stop() {
        guard isCapturing else { return }
        webView.evaluateJavaScript("stopCapture(); 0")
        finish(reason: "stopped")
    }

    func tearDown() {
        stop()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "capture")
        webView.removeFromSuperview()
    }

    private func finish(reason: String) {
        heartbeat?.invalidate()
        heartbeat = nil
        guard isCapturing else { return }
        isCapturing = false
        onEnded?(reason)
    }

    fileprivate func handle(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            onReady?()
        case "started":
            onStarted?()
        case "audio":
            guard isCapturing, let base64 = message["data"] as? String, let data = Data(base64Encoded: base64) else { return }
            onAudio?(data, (message["rms"] as? NSNumber)?.floatValue ?? 0)
        case "interrupted", "failed":
            finish(reason: "\(type): \(message["reason"] as? String ?? "unknown")")
        default:
            break
        }
    }

    private static let page = """
    <!doctype html><html><body><script>
    const targetRate = \(Int(sampleRate));
    const post = message => window.webkit.messageHandlers.capture.postMessage(message);
    const encode = samples => {
      const bytes = new Uint8Array(samples.buffer, 0, samples.length * 2);
      let binary = '';
      for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      return btoa(binary);
    };
    let lastHeartbeat = performance.now();
    window.captureHeartbeat = () => { lastHeartbeat = performance.now(); };
    let stopCapture = () => {};
    window.stopCapture = () => stopCapture();
    window.startCapture = async () => {
      let stopping = false, stream, context, source, processor, sink, watchdog;
      const audioSession = navigator.audioSession;
      const previousType = audioSession?.type ?? 'auto';
      const cleanup = () => {
        if (stopping) return;
        stopping = true;
        clearInterval(watchdog);
        if (processor) { processor.onaudioprocess = null; processor.disconnect(); }
        source?.disconnect();
        sink?.disconnect();
        stream?.getTracks().forEach(track => track.stop());
        context?.close().catch(() => {});
        try { if (audioSession) audioSession.type = previousType; } catch (_) {}
      };
      const interrupted = reason => { if (!stopping) { cleanup(); post({ type: 'interrupted', reason }); } };
      stopCapture = cleanup;
      try {
        try { if (audioSession) audioSession.type = 'play-and-record'; } catch (_) {}
        stream = await navigator.mediaDevices.getUserMedia({
          audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
        });
        if (stopping) { stream.getTracks().forEach(track => track.stop()); return; }
        const track = stream.getAudioTracks()[0];
        track.onended = () => interrupted('track-ended');
        // Defer the AudioContext until capture: creating one can take audio focus.
        context = new AudioContext({ latencyHint: 'interactive' });
        await context.resume();
        processor = context.createScriptProcessor(1024, 1, 1);
        sink = context.createGain();
        sink.gain.value = 0;
        processor.connect(sink);
        sink.connect(context.destination);
        source = context.createMediaStreamSource(stream);
        source.connect(processor);
        context.onstatechange = () => { if (context.state !== 'running') interrupted('context-' + context.state); };
        if (audioSession) audioSession.onstatechange = () => { if (audioSession.state === 'interrupted') interrupted('audio-session-interrupted'); };
        lastHeartbeat = performance.now();
        watchdog = setInterval(() => { if (performance.now() - lastHeartbeat > 3000) interrupted('native-heartbeat-expired'); }, 500);
        const step = context.sampleRate / targetRate;
        let position = 0, sum = 0, count = 0;
        processor.onaudioprocess = event => {
          const input = event.inputBuffer.getChannelData(0);
          const output = new Int16Array(Math.ceil(input.length / step) + 1);
          let written = 0, energy = 0;
          for (const sample of input) {
            energy += sample * sample; sum += sample; count += 1; position += 1;
            if (position >= step) {
              position -= step;
              output[written++] = Math.max(-1, Math.min(1, sum / count)) * 32767;
              sum = 0; count = 0;
            }
          }
          if (written > 0) post({ type: 'audio', data: encode(output.subarray(0, written)), rms: Math.sqrt(energy / input.length) });
        };
        post({ type: 'started', sampleRate: context.sampleRate });
      } catch (error) {
        if (stopping) return;
        cleanup();
        post({ type: 'failed', reason: error.name + ': ' + error.message });
      }
    };
    post({ type: 'ready' });
    </script></body></html>
    """
}

extension WebAudioCapture: WKUIDelegate, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        finish(reason: "web content process terminated")
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://foldboard-dictation.invalid/"))
    }
}

/// Breaks the retain cycle between `WKUserContentController` and its handler.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebAudioCapture?
    init(_ target: WebAudioCapture) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.handle(message.body) }
    }
}

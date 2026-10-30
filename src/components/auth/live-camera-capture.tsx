import { useEffect, useRef, useState } from "react";
import { Camera, CameraOff, CheckCircle2, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";

export function LiveCameraCapture({ onCapture }: { onCapture: (file: File | null) => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const capturedUrlRef = useRef<string | null>(null);
  const [error, setError] = useState("");
  const [active, setActive] = useState(false);
  const [captured, setCaptured] = useState<string | null>(null);

  const stopCamera = () => {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    setActive(false);
  };

  useEffect(() => () => {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    if (capturedUrlRef.current) URL.revokeObjectURL(capturedUrlRef.current);
  }, []);

  const startCamera = async () => {
    setError("");
    if (!navigator.mediaDevices?.getUserMedia) {
      setError("This browser or device does not support camera capture. Use a supported browser with camera permission.");
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: { facingMode: "user", width: { ideal: 1280 }, height: { ideal: 1280 } }
      });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }
      setActive(true);
    } catch (reason) {
      const name = reason instanceof DOMException ? reason.name : "";
      setError(name === "NotAllowedError"
        ? "Camera permission was denied. Allow camera access in your browser's site settings and try again."
        : name === "NotFoundError"
          ? "No camera was found on this device. Gallery upload is not accepted for first-time registration."
          : "The camera could not be started. Check that another app is not using it, then try again.");
    }
  };

  const capture = () => {
    const video = videoRef.current;
    if (!video || video.videoWidth === 0 || video.videoHeight === 0) {
      setError("Wait until the camera preview is ready, then capture your photo.");
      return;
    }
    const canvas = document.createElement("canvas");
    const edge = Math.min(video.videoWidth, video.videoHeight);
    const sx = (video.videoWidth - edge) / 2;
    const sy = (video.videoHeight - edge) / 2;
    canvas.width = 720;
    canvas.height = 720;
    const context = canvas.getContext("2d");
    if (!context) {
      setError("This browser could not prepare the camera image.");
      return;
    }
    context.drawImage(video, sx, sy, edge, edge, 0, 0, 720, 720);
    canvas.toBlob((blob) => {
      if (!blob) {
        setError("Camera capture failed. Please try again.");
        return;
      }
      const file = new File([blob], "profile-capture.jpg", { type: "image/jpeg" });
      if (capturedUrlRef.current) URL.revokeObjectURL(capturedUrlRef.current);
      const previewUrl = URL.createObjectURL(blob);
      capturedUrlRef.current = previewUrl;
      setCaptured(previewUrl);
      onCapture(file);
      stopCamera();
    }, "image/jpeg", 0.88);
  };

  return <div className="camera-capture">
    {error && <Alert tone="warning">{error}</Alert>}
    <div className="camera-preview">
      <video ref={videoRef} autoPlay playsInline muted aria-label="Live front camera preview" style={{ display: captured ? "none" : "block" }} />
      {captured && <img src={captured} alt="Captured profile preview" />}
      {!captured && !active && <div className="camera-placeholder"><Camera size={28}/><span>Camera preview will appear here</span></div>}
    </div>
    <div className="camera-actions">
      {!captured && !active && <Button type="button" onClick={startCamera}><Camera size={16}/> Allow camera & start</Button>}
      {active && <Button type="button" onClick={capture}><CheckCircle2 size={16}/> Capture live photo</Button>}
      {captured && <Button type="button" variant="outline" onClick={() => { if (capturedUrlRef.current) URL.revokeObjectURL(capturedUrlRef.current); capturedUrlRef.current = null; setCaptured(null); onCapture(null); void startCamera(); }}><RefreshCw size={16}/> Retake photo</Button>}
      {active && <Button type="button" variant="ghost" onClick={stopCamera}><CameraOff size={16}/> Stop camera</Button>}
    </div>
    <p className="ss-field-hint">A live camera capture is required. Gallery uploads are not accepted. Camera capture is not a biometric liveness check.</p>
  </div>;
}

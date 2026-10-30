import { useEffect, useRef, useState } from "react";
import { BrowserQRCodeReader, type IScannerControls } from "@zxing/browser";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";

type Props = { onScan: (value: string) => void; onClose: () => void };

export function QRCodeScanner({ onScan, onClose }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const controlsRef = useRef<IScannerControls | null>(null);
  const [error, setError] = useState("");
  const onScanRef = useRef(onScan);
  onScanRef.current = onScan;

  useEffect(() => {
    let disposed = false;
    let reader: BrowserQRCodeReader | null = null;

    const start = async () => {
      if (!videoRef.current) return;
      try {
        reader = new BrowserQRCodeReader();
        const controls = await reader.decodeFromVideoDevice(undefined, videoRef.current, (result, scanError) => {
          if (disposed || !result) {
            if (scanError && scanError.name !== "NotFoundException") {
              setError("Camera scan failed. Try the one-time OTP fallback.");
            }
            return;
          }
          controlsRef.current?.stop();
          onScanRef.current(result.getText());
        });
        if (disposed) controls.stop();
        else controlsRef.current = controls;
      } catch {
        if (!disposed) setError("Camera permission is unavailable. Use the OTP fallback instead.");
      }
    };

    void start();
    return () => {
      disposed = true;
      controlsRef.current?.stop();
      controlsRef.current = null;
      reader = null;
    };
  }, []);

  return <div className="surface" style={{ padding: "1rem", display: "grid", gap: ".75rem" }}>
    <div><strong>Scan the other participant’s handover QR</strong><p className="muted">Allow camera access. The QR is verified by ShelfShare’s server and can only be used once.</p></div>
    <video ref={videoRef} muted playsInline style={{ width: "100%", maxHeight: 320, borderRadius: 12, background: "#111" }} />
    {error && <Alert tone="warning">{error}</Alert>}
    <Button variant="outline" onClick={onClose}>Close scanner</Button>
  </div>;
}

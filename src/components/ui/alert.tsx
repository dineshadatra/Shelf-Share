import type {ReactNode} from "react";
import {Info,TriangleAlert,CheckCircle2,CircleX} from "lucide-react";

export function Alert({tone="info",title,children}:{tone?:"info"|"warning"|"success"|"error";title?:string;children:ReactNode}){
  const Icon=tone==="warning"?TriangleAlert:tone==="success"?CheckCircle2:tone==="error"?CircleX:Info;
  return <div className={"ss-alert ss-alert-"+tone} role={tone==="error"?"alert":"status"}><Icon size={18}/><div>{title&&<strong>{title}</strong>}<div>{children}</div></div></div>;
}

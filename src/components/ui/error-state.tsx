import {CircleAlert,RefreshCw} from "lucide-react";
import {Button} from "@/components/ui/button";

export function ErrorState({title="Something didn’t load",description="Please try again. Your information has not been changed.",onRetry}:{title?:string;description?:string;onRetry?:()=>void}){
  return <section className="ss-empty ss-error-state" role="alert" aria-live="assertive">
    <CircleAlert size={28}/>
    <h3>{title}</h3>
    <p>{description}</p>
    {onRetry&&<Button variant="outline" size="sm" onClick={onRetry}><RefreshCw size={14}/> Try again</Button>}
  </section>;
}

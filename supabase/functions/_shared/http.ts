const CORS={
 "Access-Control-Allow-Origin":"*",
 "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
 "Access-Control-Allow-Methods":"POST, OPTIONS",
 "Access-Control-Max-Age":"600",
 "Vary":"Origin"
};
export function requirePost(req:Request):Response|null{
 if(req.method==="OPTIONS")return new Response("ok",{status:204,headers:CORS});
 if(req.method!=="POST")return new Response(JSON.stringify({error:"method_not_allowed"}),{status:405,headers:{...CORS,"Content-Type":"application/json"}});
 return null;
}
export async function readJson<T>(req:Request):Promise<T>{
 const length=Number(req.headers.get("Content-Length")??0);
 if(length>20000)throw new Error("request_too_large");
 const raw=await req.text();if(raw.length>20000)throw new Error("request_too_large");
 try{return JSON.parse(raw) as T;}catch{throw new Error("invalid_json");}
}
export function jsonResponse(body:unknown,status=200):Response{
 return new Response(JSON.stringify(body),{status,headers:{...CORS,"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store","X-Content-Type-Options":"nosniff"}});
}
export function errorResponse(error:unknown,status=400):Response{
 const message=error instanceof Error?error.message:"request_failed";
 return jsonResponse({error:message.slice(0,180)},status);
}

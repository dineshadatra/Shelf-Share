import { useCallback, useEffect, useMemo, useState, type ChangeEvent, type FormEvent } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { Camera, Info, LoaderCircle, Search, ShieldCheck, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { MemberLayout } from "@/layouts/member-layout";
import { PageHeading } from "./page-helpers";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { useAuth } from "@/contexts/auth-context";
import { supabase } from "@/lib/supabase";
import { fetchOpenLibraryMetadata, normalizeIsbn, sanitiseListingPhoto, type BookMetadata } from "@/lib/catalogue";

type City = { id: string; name: string; state_name: string };
type Locality = { id: string; name: string; city_id: string };
type Genre = { id: string; slug: string; name: string };
type SavedImage = { id?: string; url?: string; moderation_status?: string };
type ListingRow = {
  id: string; condition: string; city_id: string; locality_id: string; title: string;
  authors: string[]; isbn13: string | null; edition: string | null; publisher: string | null;
  cover_image_url: string | null; images: SavedImage[];
  pricing: Record<string, number | null> | null;
  details: { existing_damage?: string; original_price_paise?: number; requested_deposit_paise?: number; ownership_declaration_type?: string } | null;
};
const blankTitle: BookMetadata = { isbn13:"", title:"", authors:[], publisher:"", edition:"", publicationYear:"", languageCode:"en", description:"", coverImageUrl:"", metadataSource:"manual", metadataSourceId:"" };
const toPaise = (value:string) => value.trim() ? Math.round(Number(value)*100) : null;
const fromPaise = (value:number|null|undefined) => value == null ? "" : String(value/100);

export default function ListBookPage() {
  const { user, verification } = useAuth();
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const editingId = params.get("id");
  const [title,setTitle] = useState<BookMetadata>(blankTitle);
  const [isbn,setIsbn] = useState("");
  const [genre,setGenre] = useState("");
  const [condition,setCondition] = useState("good");
  const [copyDescription,setCopyDescription] = useState("");
  const [damage,setDamage] = useState("");
  const [acquisitionYear,setAcquisitionYear] = useState("");
  const [ownerReference,setOwnerReference] = useState("");
  const [cityId,setCityId] = useState("");
  const [localityId,setLocalityId] = useState("");
  const [cities,setCities] = useState<City[]>([]);
  const [localities,setLocalities] = useState<Locality[]>([]);
  const [genres,setGenres] = useState<Genre[]>([]);
  const [price3,setPrice3] = useState("");
  const [price7,setPrice7] = useState("");
  const [price15,setPrice15] = useState("");
  const [price30,setPrice30] = useState("");
  const [customDaily,setCustomDaily] = useState("");
  const [minDays,setMinDays] = useState("");
  const [maxDays,setMaxDays] = useState("");
  const [originalPrice,setOriginalPrice] = useState("");
  const [requestedDeposit,setRequestedDeposit] = useState("");
  const [declaration,setDeclaration] = useState<"lawful_owner"|"authorised_to_rent">("lawful_owner");
  const [accepted,setAccepted] = useState(false);
  const [photos,setPhotos] = useState<File[]>([]);
  const [savedImages,setSavedImages] = useState<SavedImage[]>([]);
  const [evidence,setEvidence] = useState<File|null>(null);
  const [copyId,setCopyId] = useState<string|null>(editingId);
  const [busy,setBusy] = useState(false);
  const [metadataBusy,setMetadataBusy] = useState(false);
  const [loading,setLoading] = useState(true);
  const [error,setError] = useState("");
  const verified = verification?.status === "verified" && verification.age_eligible === true;
  const city = useMemo(()=>cities.find(x=>x.id===cityId),[cities,cityId]);

  useEffect(()=>{
    if(!supabase){setLoading(false);return;}
    Promise.all([
      supabase.from("cities").select("id,name,state_name").eq("is_active",true).eq("status","active").order("name"),
      supabase.from("categories").select("id,slug,name").eq("is_active",true).order("name"),
    ]).then(([c,g])=>{
      setCities((c.data??[]) as City[]); setGenres((g.data??[]) as Genre[]);
      if(c.data?.[0] && !cityId) setCityId(c.data[0].id);
    }).finally(()=>setLoading(false));
  },[]);
  useEffect(()=>{
    if(!supabase||!cityId){setLocalities([]);return;}
    supabase.from("localities").select("id,name,city_id").eq("city_id",cityId).eq("is_active",true).order("name")
      .then(({data})=>setLocalities((data??[]) as Locality[]));
  },[cityId]);

  const loadDraft=useCallback(async()=>{
    if(!supabase||!editingId)return;
    setLoading(true);
    const {data,error:invokeError}=await supabase.functions.invoke("catalogue-api",{body:{action:"owner_listings"}});
    if(invokeError){setError(invokeError.message);setLoading(false);return;}
    const row=((data?.listings??[]) as ListingRow[]).find(x=>x.id===editingId);
    if(!row){setError("Listing not found in your owner workspace.");setLoading(false);return;}
    setCopyId(row.id);
    setTitle(old=>({...old,title:row.title,authors:row.authors??[],isbn13:row.isbn13??"",edition:row.edition??"",publisher:row.publisher??"",coverImageUrl:row.cover_image_url??""}));
    setIsbn(row.isbn13??"");setCondition(row.condition);setCityId(row.city_id);setLocalityId(row.locality_id);setSavedImages(row.images??[]);
    setDamage(row.details?.existing_damage??"");setOriginalPrice(fromPaise(row.details?.original_price_paise));
    setRequestedDeposit(fromPaise(row.details?.requested_deposit_paise));
    setDeclaration(row.details?.ownership_declaration_type==="authorised_to_rent"?"authorised_to_rent":"lawful_owner");
    setPrice3(fromPaise(row.pricing?.rental_3d_paise));setPrice7(fromPaise(row.pricing?.rental_7d_paise));
    setPrice15(fromPaise(row.pricing?.rental_15d_paise));setPrice30(fromPaise(row.pricing?.rental_30d_paise));
    setCustomDaily(fromPaise(row.pricing?.custom_daily_paise));setLoading(false);
  },[editingId]);
  useEffect(()=>{if(editingId)void loadDraft();},[editingId,loadDraft]);

  const lookup=async()=>{
    setError("");
    try{
      const isbn13=normalizeIsbn(isbn);setIsbn(isbn13);setMetadataBusy(true);
      const data=await fetchOpenLibraryMetadata(isbn13);
      setTitle(old=>({...old,...data,title:data.title||old.title,authors:data.authors.length?data.authors:old.authors,publisher:data.publisher||old.publisher,edition:data.edition||old.edition,publicationYear:data.publicationYear||old.publicationYear,languageCode:data.languageCode||old.languageCode,description:data.description||old.description,coverImageUrl:data.coverImageUrl||old.coverImageUrl}));
      toast.success("Metadata found. Review and edit before saving.");
    }catch(e){setError(e instanceof Error?e.message:"Lookup failed. Enter the book details manually.");}
    finally{setMetadataBusy(false);}
  };
  const addPhotos=(event:ChangeEvent<HTMLInputElement>)=>{
    const selected=Array.from(event.target.files??[]);
    if(selected.length+photos.length+savedImages.length>5){setError("Maximum five photos per physical copy.");event.target.value="";return;}
    setPhotos(old=>[...old,...selected]);event.target.value="";
  };

  const save=async(submit:boolean)=>{
    setError("");
    if(!supabase||!user){setError("Sign in to manage your listings.");return;}
    if(!verified){setError("An active, verified and age-eligible account is required to list books.");return;}
    if(!title.title.trim()||!title.authors.some(x=>x.trim())||!genre||!cityId||!localityId){setError("Complete the title, author, genre, city and locality.");return;}
    if(!accepted){setError("Accept the lawful ownership or rental-authority declaration.");return;}
    const values=[price3,price7,price15,price30,customDaily].map(x=>x.trim()?Number(x):0);
    if(!values.some(x=>Number.isFinite(x)&&x>0)||values.some(x=>!Number.isFinite(x)||x<0)){setError("Enter at least one positive rental price. Negative prices are not allowed.");return;}
    if((minDays||maxDays)&&(!customDaily||!minDays||!maxDays||Number(minDays)<1||Number(maxDays)<Number(minDays)||Number(maxDays)>90)){setError("Custom pricing needs a daily rate and a valid 1–90 day range.");return;}
    if(submit&&photos.length+savedImages.length<2){setError("At least two actual photos are required before submission.");return;}
    setBusy(true);
    try{
      const authors=title.authors.map(x=>x.trim()).filter(Boolean);
      const {data:savedId,error:saveError}=await supabase.rpc("save_book_listing",{
        p_book_copy_id:copyId,
        p_title:{isbn13:title.isbn13?normalizeIsbn(title.isbn13):null,title:title.title.trim(),subtitle:null,edition:title.edition.trim(),authors,publisher:title.publisher.trim(),language_code:title.languageCode.trim(),publication_year:title.publicationYear.trim(),description:title.description.trim(),cover_image_url:title.coverImageUrl.trim(),metadata_source:title.metadataSource,metadata_source_id:title.metadataSourceId,genre},
        p_copy:{condition,city_id:cityId,locality_id:localityId,description:copyDescription.trim(),owner_reference:ownerReference.trim(),acquisition_year:acquisitionYear.trim()},
        p_pricing:{rental_3d_paise:toPaise(price3),rental_7d_paise:toPaise(price7),rental_15d_paise:toPaise(price15),rental_30d_paise:toPaise(price30),custom_daily_paise:toPaise(customDaily),min_custom_days:minDays||null,max_custom_days:maxDays||null},
        p_listing_details:{existing_damage:damage.trim(),original_price_paise:toPaise(originalPrice),requested_deposit_paise:toPaise(requestedDeposit)??0},
        p_declaration_type:declaration,
      });
      if(saveError)throw saveError;
      const id=savedId as string;setCopyId(id);
      let imageCount=savedImages.length;
      for(let index=0;index<photos.length;index++){
        const file=photos[index];const blob=await sanitiseListingPhoto(file);
        const key=user.id+"/"+id+"/"+crypto.randomUUID()+".jpg";
        const {error:uploadError}=await supabase.storage.from("book-listing-public").upload(key,blob,{contentType:"image/jpeg",cacheControl:"3600",upsert:false});
        if(uploadError)throw uploadError;
        const {data:imageId,error:imageError}=await supabase.rpc("register_book_listing_image",{p_book_copy_id:id,p_object_key:key,p_alt_text:title.title+" physical copy",p_is_cover:imageCount===0,p_display_order:imageCount});
        if(imageError)throw imageError;
        setSavedImages(old=>[...old,{id:imageId as string,moderation_status:"pending_review"}]);
        imageCount+=1;
      }
      setPhotos([]);
      if(evidence){
        const ext=evidence.name.split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g,"")||"bin";
        const key=user.id+"/"+id+"/evidence/"+crypto.randomUUID()+"."+ext;
        const {error:uploadError}=await supabase.storage.from("listing-evidence-private").upload(key,evidence,{contentType:evidence.type||"application/octet-stream",upsert:false});
        if(uploadError)throw uploadError;
        const {error:registerError}=await supabase.rpc("register_book_price_evidence",{p_book_copy_id:id,p_object_key:key,p_note:"Original purchase price evidence supplied by owner"});
        if(registerError)throw registerError;
        setEvidence(null);
      }
      if(submit){
        const {error:submitError}=await supabase.rpc("submit_book_listing",{p_book_copy_id:id});
        if(submitError)throw submitError;
        toast.success("Listing submitted for manual moderation.");navigate("/owner");
      }else toast.success("Draft saved privately. It is not visible in discovery.");
    }catch(e){setError(e instanceof Error?e.message:"Could not save the listing.");}
    finally{setBusy(false);}
  };

  if(loading)return <MemberLayout mode="owner" title="List a book"><div className="surface admin-case-empty"><LoaderCircle size={22}/>Loading listing…</div></MemberLayout>;
  return <MemberLayout mode="owner" title="List a book">
    <PageHeading eyebrow="SHARE YOUR SHELF" title={editingId?"Edit your book listing.":"Add a book to the neighbourhood."} description="The edition describes a title; condition, photos, price and availability belong to your particular physical copy."/>
    {!verified&&<Alert tone="warning" title="Identity verification required">Browsing remains open, but listing creation and submission require an active verified account. <a href="/verification">Complete verification</a>.</Alert>}
    {error&&<Alert tone="error">{error}</Alert>}
    <form className="listing-form surface" onSubmit={(event:FormEvent)=>{event.preventDefault();void save(false);}}>
      <div className="form-section-heading"><span>01</span><div><h2>Catalogue edition</h2><p>ISBN metadata identifies a book edition only. It does not prove ownership.</p></div></div>
      <div className="isbn-lookup-row"><Input label="ISBN-10 or ISBN-13" name="isbn" placeholder="9780143127741" value={isbn} onChange={e=>{setIsbn(e.target.value);setTitle(old=>({...old,isbn13:e.target.value}));}}/><Button type="button" variant="outline" disabled={metadataBusy||!isbn.trim()} onClick={()=>void lookup()}><Search size={15}/>{metadataBusy?"Looking up…":"Autofill ISBN"}</Button></div>
      <Alert tone="info"><Info size={16}/>Open Library metadata is optional and editable. When no record exists, enter every field manually.</Alert>
      <div className="form-two-col listing-form-gap">
        <Input label="Title" name="title" value={title.title} onChange={e=>setTitle(old=>({...old,title:e.target.value}))} required/>
        <Input label="Authors (comma separated)" name="authors" value={title.authors.join(", ")} onChange={e=>setTitle(old=>({...old,authors:e.target.value.split(",")}))} required/>
        <Input label="Publisher" name="publisher" value={title.publisher} onChange={e=>setTitle(old=>({...old,publisher:e.target.value}))}/>
        <Input label="Edition" name="edition" value={title.edition} onChange={e=>setTitle(old=>({...old,edition:e.target.value}))}/>
        <Input label="Publication year" name="publication-year" type="number" min="1400" max="2200" value={title.publicationYear} onChange={e=>setTitle(old=>({...old,publicationYear:e.target.value}))}/>
        <Input label="Language code" name="language" placeholder="en, hi, te…" value={title.languageCode} onChange={e=>setTitle(old=>({...old,languageCode:e.target.value}))}/>
        <label className="ss-field"><span className="ss-label">Genre</span><select className="ss-input" value={genre} onChange={e=>setGenre(e.target.value)} required><option value="">Choose genre</option>{genres.map(g=><option key={g.id} value={g.slug}>{g.name}</option>)}</select></label>
        <Input label="Catalogue cover URL (optional)" name="cover" value={title.coverImageUrl} onChange={e=>setTitle(old=>({...old,coverImageUrl:e.target.value}))}/>
      </div>
      <label className="ss-field listing-form-gap"><span className="ss-label">Book description</span><textarea className="ss-input listing-textarea" rows={4} maxLength={4000} value={title.description} onChange={e=>setTitle(old=>({...old,description:e.target.value}))}/></label>

      <div className="form-section-heading"><span>02</span><div><h2>Physical copy and photographs</h2><p>Every physical copy has its own listing, even for duplicate copies of one edition.</p></div></div>
      <div className="form-two-col">
        <label className="ss-field"><span className="ss-label">Condition</span><select className="ss-input" value={condition} onChange={e=>setCondition(e.target.value)}><option value="new">New</option><option value="like_new">Like new</option><option value="good">Good</option><option value="acceptable">Acceptable</option><option value="poor">Poor</option><option value="damaged">Damaged</option></select></label>
        <Input label="Acquisition year" name="acquisition-year" type="number" min="1400" max="2200" value={acquisitionYear} onChange={e=>setAcquisitionYear(e.target.value)}/>
      </div>
      <Input label="Private owner reference" name="owner-reference" hint="Only shown in your owner workspace, e.g. shelf code." value={ownerReference} onChange={e=>setOwnerReference(e.target.value)}/>
      <label className="ss-field listing-form-gap"><span className="ss-label">Existing damage / wear to disclose</span><textarea className="ss-input listing-textarea" rows={3} maxLength={2000} value={damage} onChange={e=>setDamage(e.target.value)} placeholder="Highlighting, dog-eared pages, torn jacket…"/></label>
      <label className="ss-field"><span className="ss-label">Physical copy description (optional)</span><textarea className="ss-input listing-textarea" rows={2} maxLength={1000} value={copyDescription} onChange={e=>setCopyDescription(e.target.value)}/></label>
      <div className="listing-photo-upload"><div className="listing-photo-copy"><Camera size={20}/><div><strong>Actual photographs of this copy</strong><p>At least 2 and up to 5. Photos are re-encoded to JPEG to remove EXIF metadata.</p></div></div>
        <label className="ss-button ss-button-outline listing-file-label">Add photos<input aria-label="Add actual book photos" type="file" accept="image/jpeg,image/png,image/webp" multiple onChange={addPhotos}/></label>
        <div className="listing-photo-previews">{savedImages.map((image,index)=><div className="listing-photo-thumb" key={image.id??index}>{image.url&&<img src={image.url} alt="Saved book photo"/>}<Badge tone="neutral">{image.moderation_status??"Saved"}</Badge></div>)}{photos.map((file,index)=><div className="listing-photo-thumb" key={file.name+file.lastModified}><span>{file.name}</span><button type="button" aria-label="Remove selected photo" onClick={()=>setPhotos(old=>old.filter((_,i)=>i!==index))}><Trash2 size={14}/></button></div>)}</div>
      </div>

      <div className="form-section-heading"><span>03</span><div><h2>Original price evidence</h2><p>Optional; this is not proof of ownership.</p></div></div>
      <div className="form-two-col"><Input label="Original purchase price (₹)" name="original-price" type="number" min="0" step="0.01" value={originalPrice} onChange={e=>setOriginalPrice(e.target.value)}/><label className="ss-field"><span className="ss-label">Purchase evidence (optional)</span><input className="ss-input listing-native-file" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" onChange={e=>setEvidence(e.target.files?.[0]??null)}/>{evidence&&<small>{evidence.name}</small>}</label></div>
      <div className="form-section-heading"><span>04</span><div><h2>Rental price and deposit request</h2><p>Rental rates use INR. Deposit feature remains disabled.</p></div></div>
      <div className="form-two-col">
        <Input label="3-day rental (₹)" name="price3" type="number" min="0" step="0.01" value={price3} onChange={e=>setPrice3(e.target.value)}/>
        <Input label="7-day rental (₹)" name="price7" type="number" min="0" step="0.01" value={price7} onChange={e=>setPrice7(e.target.value)}/>
        <Input label="15-day rental (₹)" name="price15" type="number" min="0" step="0.01" value={price15} onChange={e=>setPrice15(e.target.value)}/>
        <Input label="30-day rental (₹)" name="price30" type="number" min="0" step="0.01" value={price30} onChange={e=>setPrice30(e.target.value)}/>
        <Input label="Custom daily rate (₹)" name="custom" type="number" min="0" step="0.01" value={customDaily} onChange={e=>setCustomDaily(e.target.value)}/>
        <div className="form-two-col"><Input label="Min custom days" name="mindays" type="number" min="1" max="90" value={minDays} onChange={e=>setMinDays(e.target.value)}/><Input label="Max custom days" name="maxdays" type="number" min="1" max="90" value={maxDays} onChange={e=>setMaxDays(e.target.value)}/></div>
        <Input label="Requested deposit (₹ — not charged)" name="deposit" type="number" min="0" step="0.01" value={requestedDeposit} onChange={e=>setRequestedDeposit(e.target.value)} hint="A draft request only; no payment or renter-facing deposit is created."/>
      </div>
      <Alert tone="warning">Deposit custody, collection and release remain disabled pending legal and payment-provider approval. This request is never charged or presented as payable.</Alert>

      <div className="form-section-heading"><span>05</span><div><h2>Handover locality</h2><p>Exact residential addresses and personal GPS coordinates are not published.</p></div></div>
      <div className="form-two-col">
        <label className="ss-field"><span className="ss-label">City</span><select className="ss-input" value={cityId} onChange={e=>{setCityId(e.target.value);setLocalityId("");}}><option value="">Choose city</option>{cities.map(c=><option key={c.id} value={c.id}>{c.name}, {c.state_name}</option>)}</select></label>
        <label className="ss-field"><span className="ss-label">Locality</span><select className="ss-input" value={localityId} onChange={e=>setLocalityId(e.target.value)}><option value="">Choose locality</option>{localities.map(l=><option key={l.id} value={l.id}>{l.name}</option>)}</select></label>
      </div>
      {city&&<small className="ss-field-hint">Selected market: {city.name}. Approved public handover points are maintained separately by ShelfShare.</small>}
      <Alert tone="info">Availability is managed after saving: block dates for personal use or maintenance from the Owner workspace. Readers can browse using a city/locality without granting location permission.</Alert>

      <div className="listing-declaration"><h3><ShieldCheck size={17}/> Owner declaration (required)</h3>
        <label><input type="radio" name="declaration" checked={declaration==="lawful_owner"} onChange={()=>setDeclaration("lawful_owner")}/> I am the lawful owner of this physical copy.</label>
        <label><input type="radio" name="declaration" checked={declaration==="authorised_to_rent"} onChange={()=>setDeclaration("authorised_to_rent")}/> I have lawful authority to rent this physical copy.</label>
        <label className="listing-declaration-accept"><input type="checkbox" checked={accepted} onChange={e=>setAccepted(e.target.checked)}/> I declare that this is true, I may lawfully lend this exact copy and I have disclosed its existing condition and damage.</label>
        <small>ISBN metadata, purchase price and publisher records identify a book edition or transaction; none is accepted as proof of ownership.</small>
      </div>
      <div className="form-actions listing-submit-actions"><Button type="submit" variant="outline" disabled={busy||!verified}>{busy?"Saving…":"Save draft"}</Button><Button type="button" disabled={busy||!verified||!accepted} onClick={()=>void save(true)}>{busy?"Saving…":"Submit for moderation"}</Button><span>{copyId?"Editing copy "+copyId.slice(0,8):"Drafts stay private until approval."}</span></div>
    </form>
  </MemberLayout>;
}

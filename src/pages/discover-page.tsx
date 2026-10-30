import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { CalendarDays, ChevronLeft, ChevronRight, Compass, Heart, ListFilter, LocateFixed, Map, MapPin, Search, SlidersHorizontal, Sparkles } from "lucide-react";
import { PublicLayout } from "@/layouts/public-layout";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeading } from "./page-helpers";
import { supabase } from "@/lib/supabase";
import { normalizeIsbn } from "@/lib/catalogue";
import { useAuth } from "@/contexts/auth-context";

type City = { id: string; name: string; state_name: string };
type Locality = { id: string; name: string; city_id: string };
type Genre = { id: string; slug: string; name: string };
type Listing = {
  id: string; book_title_id: string; title: string; authors: string[]; isbn13: string | null;
  publisher: string | null; edition: string | null; publication_year: number | null;
  language_code: string | null; description: string | null; copy_description: string | null;
  cover_image_url: string | null; genres: string; condition: string; existing_damage: string | null;
  price_paise: number; city: string; locality: string; latitude: number | null; longitude: number | null;
  distance_km: number | null; owner_verified: boolean; images: Array<{url:string;alt_text:string|null;is_cover:boolean}>;
};
type Bundle = { id:string; name:string; description:string|null; city:string; items:Array<{copy_id:string;title:string;author:string;locality:string}> };
type Result = { total:number; page:number; page_size:number; results:Listing[] };
const INR = new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:2});
const todayInIndia = (date:Date) => {
  const parts = new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Kolkata",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(date);
  const values = Object.fromEntries(parts.map(p=>[p.type,p.value]));
  return values.year+"-"+values.month+"-"+values.day;
};
const indiaStart = (date:string) => date ? date+"T00:00:00+05:30" : "";
const indiaEnd = (date:string) => date ? date+"T23:59:59+05:30" : "";
function weekendRange() {
  const now=new Date();
  const day=Number(new Intl.DateTimeFormat("en-US",{timeZone:"Asia/Kolkata",weekday:"short"}).format(now)==="Sun"?0:
    new Intl.DateTimeFormat("en-US",{timeZone:"Asia/Kolkata",weekday:"short"}).format(now)==="Mon"?1:
    new Intl.DateTimeFormat("en-US",{timeZone:"Asia/Kolkata",weekday:"short"}).format(now)==="Tue"?2:
    new Intl.DateTimeFormat("en-US",{timeZone:"Asia/Kolkata",weekday:"short"}).format(now)==="Wed"?3:
    new Intl.DateTimeFormat("en-US",{timeZone:"Asia/Kolkata",weekday:"short"}).format(now)==="Thu"?4:
    new Intl.DateTimeFormat("en-US",{timeZone:"Asia/Kolkata",weekday:"short"}).format(now)==="Fri"?5:6);
  const start=new Date(now.getTime()+((6-day+7)%7)*86400000);
  const saturday=todayInIndia(start);
  const sunday=new Date(start.getTime()+2*86400000);
  return {from:saturday,until:todayInIndia(sunday)};
}

export default function DiscoverPage() {
  const { user }=useAuth();
  const [params]=useSearchParams();
  const [query,setQuery]=useState(params.get("query")??"");
  const [author,setAuthor]=useState("");
  const [isbn,setIsbn]=useState("");
  const [city,setCity]=useState(params.get("city")??"");
  const [locality,setLocality]=useState("");
  const [genre,setGenre]=useState("");
  const [language,setLanguage]=useState("");
  const [edition,setEdition]=useState("");
  const [condition,setCondition]=useState("");
  const [minPrice,setMinPrice]=useState("");
  const [maxPrice,setMaxPrice]=useState("");
  const [duration,setDuration]=useState("");
  const [fromDate,setFromDate]=useState("");
  const [untilDate,setUntilDate]=useState("");
  const [radius,setRadius]=useState("10");
  const [coordinates,setCoordinates]=useState<{latitude:number;longitude:number}|null>(null);
  const [locationMessage,setLocationMessage]=useState("Browse by city or locality. Location permission is optional.");
  const [cities,setCities]=useState<City[]>([]);
  const [localities,setLocalities]=useState<Locality[]>([]);
  const [genres,setGenres]=useState<Genre[]>([]);
  const [data,setData]=useState<Result>({total:0,page:1,page_size:12,results:[]});
  const [bundles,setBundles]=useState<Bundle[]>([]);
  const [loading,setLoading]=useState(false);
  const [error,setError]=useState("");
  const [filtersOpen,setFiltersOpen]=useState(false);
  const [mapView,setMapView]=useState(false);
  const [sort,setSort]=useState("recommended");
  const [page,setPage]=useState(1);
  const [saved,setSaved]=useState<string[]>([]);
  const [savingId,setSavingId]=useState("");
  const [nearbyRequested,setNearbyRequested]=useState(false);
  const [applyWeekend,setApplyWeekend]=useState(false);
  const initialLoadDone=useRef(false);
  const previousAutoSearch=useRef<{sort:string;city:string;coordinates:{latitude:number;longitude:number}|null}>({sort,city,coordinates});

  useEffect(()=>{
    if(!supabase)return;
    Promise.all([
      supabase.from("cities").select("id,name,state_name").eq("is_active",true).eq("status","active").order("name"),
      supabase.from("categories").select("id,slug,name").eq("is_active",true).order("name"),
    ]).then(([c,g])=>{setCities((c.data??[]) as City[]);setGenres((g.data??[]) as Genre[]);});
  },[]);
  useEffect(()=>{
    if(!supabase||!city){setLocalities([]);setLocality("");return;}
    const cityRow=cities.find(x=>x.name===city);
    if(!cityRow){setLocalities([]);return;}
    supabase.from("localities").select("id,name,city_id").eq("city_id",cityRow.id).eq("is_active",true).order("name")
      .then(({data})=>setLocalities((data??[]) as Locality[]));
  },[city,cities]);
  useEffect(()=>{
    if(!supabase)return;
    supabase.functions.invoke("catalogue-api",{body:{action:"bundles",city:city||null}})
      .then(({data})=>setBundles((data?.bundles??[]) as Bundle[]));
  },[city]);

  const filters=useMemo(()=>{
    const cityRow=cities.find(x=>x.name===city);
    return {
      query:query.trim(),author:author.trim(),isbn:isbn.trim(),city:city||null,locality:locality||null,
      genre:genre||null,language:language.trim()||null,edition:edition.trim()||null,condition:condition||null,
      min_price_paise:minPrice?Math.round(Number(minPrice)*100):null,
      max_price_paise:maxPrice?Math.round(Number(maxPrice)*100):null,
      duration_days:duration?Number(duration):null,
      available_from:indiaStart(fromDate),available_until:indiaEnd(untilDate),
      latitude:coordinates?.latitude??null,longitude:coordinates?.longitude??null,
      radius_km:coordinates?Number(radius):null,sort,
      city_id:cityRow?.id??null,
    };
  },[query,author,isbn,city,locality,genre,language,edition,condition,minPrice,maxPrice,duration,fromDate,untilDate,coordinates,radius,sort,cities]);

  const load=useCallback(async(nextPage=1)=>{
    if(!supabase){setError("Connect Supabase to load the live catalogue.");return;}
    let submittedFilters=filters;
    if(isbn.trim()){
      try{submittedFilters={...filters,isbn:normalizeIsbn(isbn)};}
      catch(reason){setError(reason instanceof Error?reason.message:"Enter a valid ISBN-10 or ISBN-13.");return;}
    }
    if(minPrice&&Number(minPrice)<0||maxPrice&&Number(maxPrice)<0||(minPrice&&maxPrice&&Number(maxPrice)<Number(minPrice))){
      setError("Enter a valid rental price range.");return;
    }
    if((fromDate&&!untilDate)||(!fromDate&&untilDate)||(fromDate&&untilDate&&untilDate<fromDate)){
      setError("Choose both valid availability dates.");return;
    }
    setLoading(true);setError("");
    const {data:response,error:invokeError}=await supabase.functions.invoke("catalogue-api",{
      body:{action:"discover",filters:submittedFilters,page:nextPage,page_size:12},
    });
    if(invokeError){setError(invokeError.message);setLoading(false);return;}
    setData(response as Result);setPage(nextPage);setLoading(false);
  },[filters,minPrice,maxPrice,fromDate,untilDate]);
  useEffect(()=>{ if(!initialLoadDone.current){initialLoadDone.current=true;void load(1);} },[load]);
  useEffect(()=>{
    const previous=previousAutoSearch.current;
    const changed=previous.sort!==sort || previous.city!==city || previous.coordinates!==coordinates;
    previousAutoSearch.current={sort,city,coordinates};
    if(initialLoadDone.current && changed) void load(1);
  },[sort,city,coordinates,load]);

  useEffect(()=>{ if(applyWeekend && fromDate && untilDate){ void load(1); setApplyWeekend(false); } },[applyWeekend,fromDate,untilDate,load]);

  const locationOptIn=()=>{
    if(!navigator.geolocation){setLocationMessage("Location is not available in this browser. You can still browse by locality.");return;}
    setLocationMessage("Waiting for your permission…");
    navigator.geolocation.getCurrentPosition(
      position=>{
        setCoordinates({latitude:position.coords.latitude,longitude:position.coords.longitude});
        setNearbyRequested(true);setLocationMessage("Showing approximate locality distance from your selected location.");
      },
      error=>{
        setCoordinates(null);
        setLocationMessage(error.code===1?"Location permission was declined. Browse by city or locality instead.":"Could not determine location. Browse by city or locality instead.");
      },
      {enableHighAccuracy:false,timeout:10000,maximumAge:300000},
    );
  };
  const setWeekend=()=>{
    const range=weekendRange();setFromDate(range.from);setUntilDate(range.until);setPage(1);setFiltersOpen(true);setApplyWeekend(true);
  };
  const toggleWishlist=async(item:Listing)=>{
    if(!supabase)return;
    if(!user){window.location.href="/login?next=%2Fdiscover";return;}
    setSavingId(item.id);
    const {data:added,error:rpcError}=await supabase.rpc("toggle_book_wishlist",{p_book_title_id:item.book_title_id});
    if(rpcError)setError(rpcError.message);
    else setSaved(old=>added?[...old,item.book_title_id]:old.filter(x=>x!==item.book_title_id));
    setSavingId(""); 
  };
  const submitSearch=(event:FormEvent)=>{event.preventDefault();void load(1);};
  const pageCount=Math.max(1,Math.ceil(data.total/Math.max(1,data.page_size)));
  const mapItems=data.results.filter(x=>x.latitude!=null&&x.longitude!=null);
  const mapBox=useMemo(()=>{if(!mapItems.length)return null;const latitudes=mapItems.map(x=>x.latitude as number);const longitudes=mapItems.map(x=>x.longitude as number);const pad=0.015;return {west:Math.min(...longitudes)-pad,south:Math.min(...latitudes)-pad,east:Math.max(...longitudes)+pad,north:Math.max(...latitudes)+pad};},[mapItems]);

  return <PublicLayout><main className="page-container public-page discover-page">
    <PageHeading eyebrow="THE NEIGHBOURHOOD SHELF" title="Find a book worth reading." description="Explore physical copies shared by verified owners in your city. Search freely; location access is always optional."/>
    {error&&<Alert tone="error">{error}</Alert>}
    <form onSubmit={submitSearch} className="discovery-search-bar">
      <label className="discover-search"><Search size={18}/><input aria-label="Search by title author or ISBN" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Title, author, ISBN or publisher…"/></label>
      <label className="discover-city"><MapPin size={16}/><select aria-label="City" value={city} onChange={e=>{setCity(e.target.value);setLocality("");}}><option value="">All cities</option>{cities.map(x=><option key={x.id} value={x.name}>{x.name}</option>)}</select></label>
      <Button type="submit" disabled={loading}><Search size={15}/> Search</Button>
    </form>
    <div className="discover-quick-actions">
      <button type="button" className="filter-toggle" onClick={()=>setFiltersOpen(x=>!x)} aria-expanded={filtersOpen}><SlidersHorizontal size={16}/> Filters</button>
      <button type="button" className="discovery-action" onClick={setWeekend}><CalendarDays size={15}/> Weekend availability</button>
      <button type="button" className="discovery-action" onClick={()=>setSort("recommended")}><Sparkles size={15}/> Recommended</button>
      <button type="button" className="discovery-action" onClick={()=>{if(coordinates){setSort("distance");}else locationOptIn();}}><LocateFixed size={15}/> {coordinates?"Nearby books":"Use my location"}</button>
      <div className="discovery-view-toggle"><button type="button" className={!mapView?"active":""} onClick={()=>setMapView(false)}><ListFilter size={15}/> List</button><button type="button" className={mapView?"active":""} onClick={()=>setMapView(true)}><Map size={15}/> Map</button></div>
    </div>
    <p className="location-consent-note">{locationMessage}</p>
    {filtersOpen&&<form className="discovery-filter-panel" onSubmit={submitSearch}>
      <div className="form-two-col">
        <Input label="Author" name="author-filter" value={author} onChange={e=>setAuthor(e.target.value)} placeholder="Author name"/>
        <Input label="ISBN" name="isbn-filter" value={isbn} onChange={e=>setIsbn(e.target.value)} placeholder="ISBN-10 or 13"/>
        <label className="ss-field"><span className="ss-label">Locality</span><select className="ss-input" value={locality} onChange={e=>setLocality(e.target.value)}><option value="">All localities</option>{localities.map(x=><option key={x.id} value={x.name}>{x.name}</option>)}</select></label>
        <label className="ss-field"><span className="ss-label">Genre</span><select className="ss-input" value={genre} onChange={e=>setGenre(e.target.value)}><option value="">All genres</option>{genres.map(x=><option key={x.id} value={x.slug}>{x.name}</option>)}</select></label>
        <Input label="Language code" name="language-filter" placeholder="en, hi, te" value={language} onChange={e=>setLanguage(e.target.value)}/>
        <Input label="Edition" name="edition-filter" placeholder="e.g. revised" value={edition} onChange={e=>setEdition(e.target.value)}/>
        <label className="ss-field"><span className="ss-label">Condition</span><select className="ss-input" value={condition} onChange={e=>setCondition(e.target.value)}><option value="">Any condition</option><option value="new">New</option><option value="like_new">Like new</option><option value="good">Good</option><option value="acceptable">Acceptable</option><option value="poor">Poor</option><option value="damaged">Damaged</option></select></label>
        <label className="ss-field"><span className="ss-label">Rental duration</span><select className="ss-input" value={duration} onChange={e=>setDuration(e.target.value)}><option value="">Any duration</option><option value="3">3 days</option><option value="7">7 days</option><option value="15">15 days</option><option value="30">30 days</option></select></label>
        <Input label="Minimum rental (₹)" name="min-price" type="number" min="0" step="0.01" value={minPrice} onChange={e=>setMinPrice(e.target.value)}/>
        <Input label="Maximum rental (₹)" name="max-price" type="number" min="0" step="0.01" value={maxPrice} onChange={e=>setMaxPrice(e.target.value)}/>
        <Input label="Available from" name="available-from" type="date" value={fromDate} onChange={e=>setFromDate(e.target.value)}/>
        <Input label="Available until" name="available-until" type="date" value={untilDate} onChange={e=>setUntilDate(e.target.value)}/>
        <label className="ss-field"><span className="ss-label">Distance radius (km)</span><select className="ss-input" value={radius} onChange={e=>setRadius(e.target.value)}><option value="2">2 km</option><option value="5">5 km</option><option value="10">10 km</option><option value="20">20 km</option><option value="50">50 km</option></select></label>
        <label className="ss-field"><span className="ss-label">Sort by</span><select className="ss-input" value={sort} onChange={e=>setSort(e.target.value)}><option value="recommended">Recommended</option><option value="price_low">Price: low to high</option><option value="price_high">Price: high to low</option><option value="distance" disabled={!coordinates}>Distance</option></select></label>
      </div>
      <div className="discovery-filter-actions"><Button type="submit" disabled={loading}>Apply filters</Button><Button type="button" variant="ghost" onClick={()=>{setAuthor("");setIsbn("");setGenre("");setLocality("");setLanguage("");setEdition("");setCondition("");setMinPrice("");setMaxPrice("");setDuration("");setFromDate("");setUntilDate("");setCoordinates(null);setRadius("10");setSort("recommended");setPage(1);}}>Clear filters</Button></div>
    </form>}
    <div className="discover-result-meta"><span><strong>{data.total}</strong> available physical copies</span><label>Sort <select value={sort} onChange={e=>setSort(e.target.value)}><option value="recommended">Recommended</option><option value="price_low">Lowest price</option><option value="price_high">Highest price</option><option value="distance" disabled={!coordinates}>Nearest first</option></select></label></div>
    {loading?<div className="discovery-loading"><div/><div/><div/><div/></div>:data.results.length===0?<EmptyState title="No books found" description="Try another city, locality or set of filters. You can also leave a waitlist for a title."/>:
      mapView?<section className="discovery-map-view"><div className="discovery-map-heading"><Map size={18}/><div><strong>Approximate locality map</strong><p>Markers represent locality centres, not an owner’s home or exact handover point.</p></div></div>
        {mapItems.length===0?<Alert tone="info">No locality map coordinates have been configured for these results. Switch to List view or choose another area.</Alert>:
          <><div className="discovery-map-embed"><iframe title="OpenStreetMap showing approximate book localities" loading="lazy" src={"https://www.openstreetmap.org/export/embed.html?bbox="+mapBox!.west+"%2C"+mapBox!.south+"%2C"+mapBox!.east+"%2C"+mapBox!.north+"&layer=mapnik"}/></div><div className="discovery-map-pins">{mapItems.map(item=><a key={item.id} className="discovery-map-pin" href={"https://www.openstreetmap.org/?mlat="+item.latitude+"&mlon="+item.longitude+"#map=15/"+item.latitude+"/"+item.longitude} target="_blank" rel="noreferrer"><MapPin size={18}/><span><strong>{item.title}</strong><small>{item.locality}, {item.city}</small></span><b>{INR.format(item.price_paise/100)}</b></a>)}</div></>}
      </section>:
      <div className="book-grid discovery-book-grid">{data.results.map(item=><article className="book-card live-book-card" key={item.id}>
        <div className="book-card-image"><Link to={"/books/"+item.id}><img className="live-book-cover" src={item.images.find(x=>x.is_cover)?.url??item.images[0]?.url??item.cover_image_url??""} alt={item.title+" cover"} loading="lazy"/></Link><button type="button" className={"save-book "+(saved.includes(item.book_title_id)?"saved":"")} title="Add to wishlist" aria-label="Toggle wishlist" disabled={savingId===item.id} onClick={()=>void toggleWishlist(item)}><Heart size={17} fill={saved.includes(item.book_title_id)?"currentColor":"none"}/></button><span className="book-card-tag">{item.genres||"Book"}</span></div>
        <div className="book-card-body"><div className="book-card-title-row"><Link to={"/books/"+item.id} className="book-card-title">{item.title}</Link></div><p className="book-card-author">by {item.authors?.join(", ")}</p><p className="book-card-location"><MapPin size={13}/>{item.locality}, {item.city}{item.distance_km!=null?" · "+item.distance_km.toFixed(1)+" km":""}</p><div className="live-book-meta"><Badge tone="green">{item.condition.replaceAll("_"," ")}</Badge>{item.owner_verified&&<Badge tone="blue">Verified owner</Badge>}</div><div className="book-card-bottom"><strong>{INR.format(item.price_paise/100)}<small> / selected duration</small></strong><span>Physical copy</span></div></div>
      </article>)}</div>}
    <div className="discovery-pagination"><span>Page {page} of {pageCount}</span><div><Button variant="outline" size="sm" disabled={page<=1||loading} onClick={()=>void load(page-1)}><ChevronLeft size={16}/> Previous</Button><Button variant="outline" size="sm" disabled={page>=pageCount||loading} onClick={()=>void load(page+1)}>Next <ChevronRight size={16}/></Button></div></div>

    {bundles.length>0&&<section className="discovery-bundles"><div className="section-heading"><div><span className="eyebrow">READ TOGETHER</span><h2 className="serif">Book bundles</h2><p>Curated sets from one verified owner in the same city.</p></div></div><div className="bundle-grid">{bundles.map(bundle=><article className="surface bundle-card" key={bundle.id}><Badge tone="green">{bundle.city}</Badge><h3>{bundle.name}</h3><p>{bundle.description}</p><ul>{bundle.items.map(item=><li key={item.copy_id}>{item.title} <small>by {item.author}</small></li>)}</ul></article>)}</div></section>}
    {nearbyRequested&&coordinates&&<p className="location-consent-note"><Compass size={14}/> Distance uses approximate locality centres and your browser-provided location. Your coordinates are used for this search request only.</p>}
  </main></PublicLayout>;
}

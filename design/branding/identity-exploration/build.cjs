// Editable procedural vector masters. Run with the bundled Node runtime.
const fs = require('fs');
const path = require('path');
const deps = process.env.VAULTITO_DESIGN_MODULES || '/Users/michaeldonnelly/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp = require(path.join(deps, 'sharp'));
const {GlobalFonts, convertSVGTextToPath} = require(path.join(deps, '@napi-rs/canvas'));
const root = __dirname;
GlobalFonts.registerFromPath(path.join(root, 'fonts/Manrope-Regular-instance.ttf'), 'Manrope');
GlobalFonts.registerFromPath(path.join(root, 'fonts/Manrope-Semibold-instance.ttf'), 'ManropeSemibold');
const palette = ['#FF797E','#FFB56B','#E5D579','#8FD4A2','#69C8DC','#8B9DEB','#BC8CE1','#EC88B7'];
const ink = '#241E32', cream = '#FAF7F2';
const configs = [
  {id:'01-open-circle', name:'Open Circle', count:6, radius:248, arm:114, depth:146, stroke:64, bg:ink, twist:0, desc:'Six generous Vs. The clearest silhouette at small sizes.', note:'Recommended starting point · broad spacing · calm rhythm'},
  {id:'02-prism', name:'Prism', count:8, radius:254, arm:88, depth:130, stroke:51, bg:ink, twist:0, desc:'Eight rounded Vs. A fuller, more jewel-like rainbow.', note:'Closest to a rainbow wreath · stronger gallery association'},
  {id:'03-orbit', name:'Orbit', count:12, radius:260, arm:56, depth:108, stroke:37, bg:ink, twist:12, desc:'Twelve fine Vs. A flowing spectrum with a lighter touch.', note:'Most expressive · individual Vs merge sooner at small sizes'}
];
function colorAt(t) {
  t = ((t % 1) + 1) % 1;
  let p=t*palette.length, i=Math.floor(p), f=p-i;
  const a=palette[i],b=palette[(i+1)%palette.length];
  return '#'+[1,3,5].map(k=>Math.round(parseInt(a.slice(k,k+2),16)*(1-f)+parseInt(b.slice(k,k+2),16)*f).toString(16).padStart(2,'0')).join('');
}
function mark(c, mono=null, uid='m') {
  let defs='',body='';
  for(let i=0;i<c.count;i++) {
    const y=512-c.radius, top=y-c.depth/2, bottom=y+c.depth/2;
    const id=uid+i;
    defs+=`<linearGradient id="${id}" x1="${512-c.arm}" y1="${top}" x2="${512+c.arm}" y2="${top}" gradientUnits="userSpaceOnUse"><stop stop-color="${colorAt((i-.48)/c.count)}"/><stop offset=".5" stop-color="${colorAt(i/c.count)}"/><stop offset="1" stop-color="${colorAt((i+.48)/c.count)}"/></linearGradient>`;
    body+=`<path transform="rotate(${i*360/c.count+c.twist} 512 512)" d="M${512-c.arm} ${top} L512 ${bottom} L${512+c.arm} ${top}" fill="none" stroke="${mono || `url(#${id})`}" stroke-width="${c.stroke}" stroke-linecap="round" stroke-linejoin="round"/>`;
  }
  return `<defs>${defs}</defs>${body}`;
}
function svg(w,h,body) {return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>`;}
function text(x,y,str,size=20,fill=ink,weight=400) {return `<text x="${x}" y="${y}" font-family="${weight>=600?'ManropeSemibold':'Manrope'}" font-size="${size}" fill="${fill}">${str}</text>`;}
function placedMark(c,x,y,size,mono=null,id='p') {return `<g transform="translate(${x} ${y}) scale(${size/1024})">${mark(c,mono,id)}</g>`;}
function tile(c,x,y,size,bg=c.bg,mono=null,id='t',mask=true) {
  return `<g>${mask?`<defs><clipPath id="clip${id}"><rect x="${x}" y="${y}" width="${size}" height="${size}" rx="${size*.223}"/></clipPath></defs><g clip-path="url(#clip${id})">`:'<g>'}<rect x="${x}" y="${y}" width="${size}" height="${size}" fill="${bg}"/>${placedMark(c,x,y,size,mono,id)}</g></g>`;
}
function lockup(c,x,y,size,fill=ink,id='l') {return placedMark(c,x,y,size,null,id)+text(x+size*.94,y+size*.64,'Vaultito',size*.49,fill,650);}
function save(name,s) {fs.writeFileSync(path.join(root,name),s);}
async function render(name,s,w,h) {
  const outlined=convertSVGTextToPath(s);
  save(name+'.svg',outlined);
  let im=sharp(outlined);
  if(w)im=im.resize(w,h);
  await im.flatten({background:cream}).removeAlpha().png().toFile(path.join(root,name+'.png'));
}
async function main() {
  fs.mkdirSync(path.join(root,'assets'),{recursive:true});
  fs.mkdirSync(path.join(root,'previews'),{recursive:true});
  for(const c of configs) {
    save(`assets/${c.id}-symbol.svg`,svg(1024,1024,mark(c)));
    save(`assets/${c.id}-symbol-one-color.svg`,svg(1024,1024,mark(c,ink)));
    save(`assets/${c.id}-symbol-reversed.svg`,svg(1024,1024,mark(c,cream)));
    await render(`assets/${c.id}-icon-1024`,svg(1024,1024,`<rect width="1024" height="1024" fill="${c.bg}"/>${mark(c)}`));
    const lock = svg(690,190,lockup(c,0,0,190));
    save(`assets/${c.id}-lockup-editable-text.svg`,lock);
    save(`assets/${c.id}-lockup-outlined.svg`,convertSVGTextToPath(lock));
    const wordmark=svg(510,110,text(0,85,'Vaultito',100,ink,650));
    save(`assets/${c.id}-wordmark.svg`,convertSVGTextToPath(wordmark));
    for(const size of [40,60,120]) {
      await sharp(path.join(root,`assets/${c.id}-icon-1024.png`)).resize(size,size).png().toFile(path.join(root,`previews/${c.id}-${size}px.png`));
    }
  }
  const c=configs[0];
  await render('assets/04-chalk-icon-1024',svg(1024,1024,`<rect width="1024" height="1024" fill="#EDE9E3"/>${mark(c,ink)}`));
  let board=`<rect width="1800" height="1370" fill="${cream}"/>`;
  board+=text(70,60,'VAULTITO / IDENTITY STUDY 02',18,ink,650)+text(1730,60,'18 OCT 2026',16,ink).replace('x="1730"','x="1730" text-anchor="end"');
  board+=text(70,141,'A circle of little Vs.',65,ink,650)+text(72,187,'One idea. Three rhythms. A soft spectrum, held in an open circle.',24,'#635B6D');
  configs.forEach((c,i)=> {
    const x=70+i*560;
    board+=text(x,261,`0${i+1} / ${c.name}`,25,ink,650);
    board+=tile(c,x,291,530,c.bg,null,'big'+i);
    board+=lockup(c,x+14,840,135,ink,'lock'+i);
    board+=text(x,1021,`${c.count} Vs · ${c.count===6?'spacious':c.count===8?'balanced':'delicate'}`,20,ink,650);
    board+=text(x,1060,['Best small-size starting point.','The fullest rainbow treatment.','A finer, flowing halo.'][i],19,'#635B6D');
    board+=`<rect x="${x}" y="1090" width="530" height="184" rx="20" fill="#EAE4DE"/>`;
    board+=tile(c,x+22,1118,40,c.bg,null,'40'+i)+tile(c,x+107,1108,60,c.bg,null,'60'+i)+tile(c,x+217,1100,120,c.bg,null,'120'+i);
    board+=text(x+22,1248,'40 px',15)+text(x+107,1248,'60 px',15)+text(x+243,1248,'120 px',15);
    board+=placedMark(c,x+384,1114,106,ink,'mono'+i)+text(x+369,1248,'One color',15);
  });
  board+=text(70,1328,'Original vector exploration · unselected concepts · iOS corner masks shown for preview only',17,'#635B6D');
  await render('comparison',svg(1800,1370,board));
  for(const c of configs) {
    let b=`<rect width="1440" height="1200" fill="${cream}"/>`;
    b+=text(60,62,`${c.name} / ${c.count} Vs`,36,ink,650)+text(60,104,c.desc,23,'#635B6D');
    b+=`<rect x="60" y="145" width="640" height="300" rx="20" fill="#F0EBE5"/><rect x="740" y="145" width="640" height="300" rx="20" fill="${ink}"/>`;
    b+=lockup(c,88,215,175,ink,'light')+lockup(c,768,215,175,cream,'dark');
    b+=text(101,408,'Your photos. Your keys. Your rules.',19,'#635B6D')+text(781,408,'Your photos. Your keys. Your rules.',19,'#D7CDDD');
    b+=tile(c,60,485,330,c.bg,null,'primary')+tile(c,430,485,330,'#F3ECE4',null,'lightbg')+tile(c,800,485,330,ink,cream,'mono');
    b+=text(60,852,'Primary / midnight',19)+text(430,852,'Light background study',19)+text(800,852,'Single-color test',19);
    b+=text(60,935,'At actual pixel sizes',21,ink,650)+tile(c,60,966,40,c.bg,null,'s40')+tile(c,150,956,60,c.bg,null,'s60')+tile(c,260,946,120,c.bg,null,'s120');
    b+=text(60,1110,c.note,21,'#635B6D')+text(60,1155,'Screen previews only. No claim of security certification, concealment or trademark clearance.',17,'#635B6D');
    await render('previews/'+c.id+'-sheet',svg(1440,1200,b));
  }
  // Stylized home-screen context with original generic neighboring app symbols.
  let h=`<defs><linearGradient id="wall" x2="0" y2="1"><stop stop-color="#B4C6DA"/><stop offset="1" stop-color="#EFD4BF"/></linearGradient></defs><rect width="1440" height="1150" fill="${cream}"/>`;
  h+=text(60,65,'Among the everyday.',46,ink,650)+text(60,109,'Open Circle in light and dark Home Screen studies.',23,'#635B6D');
  for(let p=0;p<2;p++) {
    const px=110+p*680,py=160;
    h+=`<rect x="${px}" y="${py}" width="460" height="920" rx="64" fill="${p?ink:'#E6D5C7'}"/><rect x="${px+12}" y="${py+12}" width="436" height="896" rx="54" fill="${p?'#373849':'url(#wall)'}"/><rect x="${px+157}" y="${py+28}" width="146" height="36" rx="18" fill="#17131E"/>`;
    h+=text(px+38,py+57,'9:41',18,p?cream:ink,650);
    for(let row=0;row<4;row++)for(let col=0;col<4;col++) {
      const x=px+35+col*102,y=py+120+row*130;
      if(row===1&&col===1) {
        h+=tile(c,x,y,76,c.bg,null,'home'+p)+text(x+38,y+100,'Vaultito',13,p?cream:ink).replace(`x="${x+38}"`,`x="${x+38}" text-anchor="middle"`);
      } else {
        const colors=['#698D9A','#C28B79','#B8A583','#918AA7','#819C88','#A5849B'];
        h+=`<rect x="${x}" y="${y}" width="76" height="76" rx="17" fill="${colors[(row*4+col)%6]}"/><path d="M${x+22} ${y+27} h32 M${x+22} ${y+39} h23 M${x+22} ${y+51} h28" stroke="#FFFFFF" stroke-opacity=".8" stroke-width="4" stroke-linecap="round"/>`;
        h+=text(x+38,y+100,['Notes','Weather','Calendar','Music'][(row+col)%4],13,p?cream:ink).replace(`x="${x+38}"`,`x="${x+38}" text-anchor="middle"`);
      }
    }
    h+=`<rect x="${px+28}" y="${py+778}" width="404" height="110" rx="34" fill="#FFFFFF" fill-opacity=".15"/>`;
    for(let i=0;i<4;i++)h+=`<rect x="${px+46+i*100}" y="${py+795}" width="76" height="76" rx="17" fill="${['#87A995','#8C9EBA','#BC9C8B','#A896BC'][i]}"/>`;
  }
  h+=text(60,1130,'Illustrative Home Screen layout. Neighboring symbols are original placeholders; masking is approximate.',16,'#635B6D');
  await render('previews/home-screen',svg(1440,1150,h));
  const cards=configs.map(c=>`<article id="${c.id}"><h2>${c.name} <small>${c.count} Vs</small></h2><p>${c.desc}</p><img src="previews/${c.id}-sheet.png" alt="${c.name} light and dark logos and size tests"><p><a href="assets/${c.id}-symbol.svg">Editable symbol SVG</a> · <a href="assets/${c.id}-lockup-outlined.svg">Outlined logo SVG</a> · <a href="assets/${c.id}-icon-1024.png">1024 PNG icon</a></p></article>`).join('');
  save('index.html',`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Vaultito — a circle of Vs</title><style>@font-face{font-family:Manrope;src:url(fonts/Manrope-Variable.ttf)}*{box-sizing:border-box}body{margin:0;background:${cream};color:${ink};font-family:Manrope,system-ui,sans-serif}main{max-width:1200px;margin:auto;padding:48px 24px}h1{font-size:clamp(40px,7vw,76px);letter-spacing:-.055em;line-height:1.08;margin:22px 0}p{line-height:1.7;max-width:800px}nav{display:flex;gap:20px;flex-wrap:wrap;margin:28px 0}a{color:#6B3878;text-underline-offset:4px}img{width:100%;height:auto;display:block}article{border-top:1px solid #D8CFD8;margin-top:60px;padding-top:22px}h2{font-size:32px}small{font-size:16px;font-weight:400;color:#716674}.eyebrow{font-size:13px;letter-spacing:.12em;text-transform:uppercase}.callout{background:#EDE5EE;padding:22px;border-radius:16px}footer{margin-top:50px;font-size:14px;color:#635B6D}</style><main><div class="eyebrow">Vaultito · October 18, 2026 · Exploration 02</div><h1>A circle of little Vs.</h1><p>Your new direction: a circular ombré rainbow of Vs. Each separate V points toward an open center. Neighboring hues blend across each mark, creating a continuous color journey without transparent overlapping petals.</p><nav>${configs.map(c=>`<a href="#${c.id}">${c.name}</a>`).join('')}<a href="#home">Home Screen</a><a href="README.md">Design notes &amp; inventory</a></nav><img src="comparison.png" alt="Three circular rainbow V arrangements side by side"><p class="callout"><strong>October 19 review: revise before release.</strong> Close rainbow-chevron and inward-arrow ring references were found at Vivid Photo Visual and ConvergeHub. These concepts are not cleared. Open Circle remains the clearest small-size study, but the family needs further differentiation. <a href="RESEMBLANCE-REVIEW-2026-10-19.md">Read the findings and search limits.</a></p>${cards}<article id="home"><h2>Everyday context</h2><img src="previews/home-screen.png" alt="Open Circle on illustrative light and dark Home Screens"></article><article><h2>A quieter option</h2><p>Chalk removes the rainbow entirely: the same six-V construction, rendered as a single ink color on warm gray. It is a candidate monochrome alternate, not a concealment feature.</p><img src="assets/04-chalk-icon-1024.png" style="max-width:240px;border-radius:22.3%" alt="Monochrome circular V icon"><a href="assets/04-chalk-icon-1024.png">Download square 1024 PNG</a></article><footer>Unselected original vector concepts. AI-assisted procedural design; no image-generation model or stock artwork used. Manrope: SIL Open Font License 1.1, bundled. Rainbow radial forms share visual territory with existing photo apps; see design notes. No trademark clearance claimed. Current app assets unchanged.</footer></main></html>`);
  console.log('Created three vector directions, four square 1024 PNG icon candidates, native-size previews, and a local presentation.');
}
main().catch(e=>{console.error(e);process.exitCode=1;});

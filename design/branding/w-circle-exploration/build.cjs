// Editable W-circle studies. Icons retain square, opaque export backgrounds.
const fs = require('fs');
const path = require('path');
const deps = process.env.VAULTITO_DESIGN_MODULES || '/Users/michaeldonnelly/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp = require(path.join(deps, 'sharp'));
const {GlobalFonts, convertSVGTextToPath} = require(path.join(deps, '@napi-rs/canvas'));
const root = __dirname;
const fonts = path.join(root, '../identity-exploration/fonts');
GlobalFonts.registerFromPath(path.join(fonts, 'Manrope-Regular-instance.ttf'), 'Manrope');
GlobalFonts.registerFromPath(path.join(fonts, 'Manrope-Semibold-instance.ttf'), 'ManropeSemibold');
const ink='#241E32', cream='#FAF7F2';
const palette=['#FF797E','#FFB56B','#E5D579','#8FD4A2','#69C8DC','#8B9DEB','#BC8CE1','#EC88B7'];
const configs=[
  {id:'01-four-ws',name:'Four / bold',count:4,radius:247,arm:151,depth:174,stroke:53,caption:'Broad Ws, with the most room to breathe.'},
  {id:'02-six-ws',name:'Six / balanced',count:6,radius:258,arm:108,depth:144,stroke:43,caption:'A fuller circle with a clear double dip.'},
  {id:'03-eight-ws',name:'Eight / spectrum',count:8,radius:268,arm:83,depth:123,stroke:33,caption:'More color rhythm; finer letter detail.'}
];
function colorAt(t){t=((t%1)+1)%1;const p=t*8,i=Math.floor(p),f=p-i,a=palette[i],b=palette[(i+1)%8];return '#'+[1,3,5].map(k=>Math.round(parseInt(a.slice(k,k+2),16)*(1-f)+parseInt(b.slice(k,k+2),16)*f).toString(16).padStart(2,'0')).join('');}
function wPath(c){const y=512-c.radius,top=y-c.depth/2,bottom=y+c.depth/2;return `M${512-c.arm} ${top} L${512-c.arm*.5} ${bottom} L512 ${top+c.depth*.25} L${512+c.arm*.5} ${bottom} L${512+c.arm} ${top}`;}
function mark(c,mono=null,uid='w'){
  let defs='',body='';
  for(let i=0;i<c.count;i++){
    const id=uid+i,y=512-c.radius-c.depth/2;
    defs+=`<linearGradient id="${id}" x1="${512-c.arm}" y1="${y}" x2="${512+c.arm}" y2="${y}" gradientUnits="userSpaceOnUse"><stop stop-color="${colorAt((i-.48)/c.count)}"/><stop offset=".5" stop-color="${colorAt(i/c.count)}"/><stop offset="1" stop-color="${colorAt((i+.48)/c.count)}"/></linearGradient>`;
    body+=`<path d="${wPath(c)}" transform="rotate(${i*360/c.count} 512 512)" fill="none" stroke="${mono||`url(#${id})`}" stroke-width="${c.stroke}" stroke-linecap="round" stroke-linejoin="round"/>`;
  }
  return `<defs>${defs}</defs>${body}`;
}
function svg(w,h,s){return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${s}</svg>`;}
function t(x,y,s,size=20,color=ink,bold=false){return `<text x="${x}" y="${y}" font-family="${bold?'ManropeSemibold':'Manrope'}" font-size="${size}" fill="${color}">${s}</text>`;}
function placed(c,x,y,size,mono=null,id='p'){return `<g transform="translate(${x} ${y}) scale(${size/1024})">${mark(c,mono,id)}</g>`;}
function tile(c,x,y,size,bg=ink,mono=null,id='t'){return `<defs><clipPath id="mask${id}"><rect x="${x}" y="${y}" width="${size}" height="${size}" rx="${size*.223}"/></clipPath></defs><g clip-path="url(#mask${id})"><rect x="${x}" y="${y}" width="${size}" height="${size}" fill="${bg}"/>${placed(c,x,y,size,mono,id)}</g>`;}
function save(name,s){fs.writeFileSync(path.join(root,name),s);}
async function render(name,s){const outlined=convertSVGTextToPath(s);save(name+'.svg',outlined);await sharp(outlined).flatten({background:cream}).removeAlpha().png().toFile(path.join(root,name+'.png'));}
async function main(){
  fs.mkdirSync(path.join(root,'assets'),{recursive:true});
  fs.mkdirSync(path.join(root,'previews'),{recursive:true});
  let b=`<rect width="1800" height="1230" fill="${cream}"/>`;
  b+=t(70,61,'W MONOGRAM / COLOR STUDY',18,ink,true)+t(1500,61,'OCTOBER 19, 2026',17);
  b+=t(70,141,'Same spectrum. A circle of Ws.',62,ink,true)+t(72,190,'Soft color, rounded strokes, and a little more wag.',24,'#635B6D');
  configs.forEach((c,i)=>{
    const x=70+i*560;
    b+=t(x,266,c.name,26,ink,true)+tile(c,x,300,530,ink,null,'hero'+i);
    b+=t(x,877,c.caption,19,'#635B6D');
    b+=`<rect x="${x}" y="910" width="530" height="210" rx="20" fill="#EAE4DE"/>`;
    b+=tile(c,x+22,950,40,ink,null,'s40'+i)+tile(c,x+105,940,60,ink,null,'s60'+i)+tile(c,x+210,929,120,ink,null,'s120'+i);
    b+=t(x+22,1089,'40 px',15)+t(x+105,1089,'60 px',15)+t(x+238,1089,'120 px',15);
    b+=placed(c,x+380,932,115,ink,'mono'+i)+t(x+371,1089,'One color',15);
  });
  b+=t(70,1180,'Explorations only · editable vector originals · approximate iOS masks shown in previews',17,'#635B6D');
  await render('comparison',svg(1800,1230,b));
  for(const c of configs){
    save(`assets/${c.id}-symbol.svg`,svg(1024,1024,mark(c)));
    save(`assets/${c.id}-one-color.svg`,svg(1024,1024,mark(c,ink)));
    await render(`assets/${c.id}-icon-1024`,svg(1024,1024,`<rect width="1024" height="1024" fill="${ink}"/>${mark(c)}`));
    for(const size of [40,60,120])await sharp(path.join(root,`assets/${c.id}-icon-1024.png`)).resize(size,size).png().toFile(path.join(root,`previews/${c.id}-${size}px.png`));
  }
  const c=configs[1];
  let s=`<rect width="1440" height="770" fill="${cream}"/>`+t(60,70,'Six Ws / background and letter checks',38,ink,true);
  s+=tile(c,60,130,340,ink,null,'dark')+tile(c,440,130,340,'#EFE8E0',null,'light')+tile(c,820,130,340,ink,cream,'reverse');
  s+=t(60,515,'Midnight',21)+t(440,515,'Warm light',21)+t(820,515,'One color',21);
  const single={...c,radius:0,arm:130,depth:170,stroke:45};
  s+=`<g transform="translate(60 567) scale(.4)"><path d="${wPath(single)}" transform="translate(-360 -390)" fill="none" stroke="${ink}" stroke-width="45" stroke-linecap="round" stroke-linejoin="round"/></g>`;
  s+=t(240,635,'One W = two joined downstrokes with a raised center.',23,'#635B6D');
  s+=t(60,725,'Changing the letter does not establish trademark clearance; this composition has not been re-screened.',17,'#635B6D');
  await render('previews/backgrounds',svg(1440,770,s));
  console.log('Exported 3 W-circle concepts, 1024px RGB icons, editable SVGs, and actual-size previews.');
}
main().catch(e=>{console.error(e);process.exitCode=1;});

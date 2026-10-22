// Presentation layout only: preserves the generated artwork unchanged.
const fs=require('fs'),path=require('path');
const deps=process.env.VAULTITO_DESIGN_MODULES||'/Users/michaeldonnelly/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(deps,'sharp'));
const {GlobalFonts,convertSVGTextToPath}=require(path.join(deps,'@napi-rs/canvas'));
const root=__dirname,fonts=path.join(root,'../../identity-exploration/fonts');
GlobalFonts.registerFromPath(path.join(fonts,'Manrope-Regular-instance.ttf'),'Manrope');
GlobalFonts.registerFromPath(path.join(fonts,'Manrope-Semibold-instance.ttf'),'ManropeSemibold');
const concepts=[
['01-little-guardian','Little Guardian','The friendly full-body mascot.'],
['02-cheeky-close-up','Cheeky Close-Up','The joke, front and center.'],
['03-caught-you-looking','Caught You Looking','A knowing glance adds character.'],
['04-wag-stamp','Wag Stamp','The simplest silhouette.']
];
function text(x,y,s,size=20,bold=false){return `<text x="${x}" y="${y}" fill="#241E32" font-family="${bold?'ManropeSemibold':'Manrope'}" font-size="${size}">${s}</text>`;}
async function main(){
let b='<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="1030"><rect width="2000" height="1030" fill="#FAF7F2"/>';
b+=text(50,55,'DOG GUARDIAN / FOUR CONCEPT MOCKUPS',17,true)+text(50,134,'Four ways to wag.',65,true)+text(52,179,'One raised tail. One keyhole. Four different personalities.',24);
const layers=[];
for(let i=0;i<concepts.length;i++){
const [id,name,caption]=concepts[i],x=50+i*485;
b+=text(x,239,`${i+1}. ${name}`,25,true)+text(x,759,caption,19);
layers.push({input:await sharp(path.join(root,id+'.png')).resize(445,445).toBuffer(),left:x,top:267});
for(const [j,size] of [40,60,120].entries()){
const sx=x+[0,95,215][j],sy=795+(120-size)/2;
const out=await sharp(path.join(root,id+'.png')).resize(size,size).png().toBuffer();
fs.writeFileSync(path.join(root,`${id}-${size}px.png`),out);
layers.push({input:out,left:sx,top:sy});
b+=text(sx,950,size+' px',15);
}
}
b+=text(50,1000,'AI-generated concept artwork · separate originals preserved · no app integration or new resemblance review',17)+'</svg>';
await sharp(convertSVGTextToPath(b)).composite(layers).png().toFile(path.join(root,'comparison.png'));
fs.writeFileSync(path.join(root,'index.html'),`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Dog guardian — four mockups</title><style>body{font:18px system-ui;background:#faf7f2;color:#241e32;max-width:1400px;margin:auto;padding:32px}img{max-width:100%;height:auto}section{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:30px}article img{border-radius:18%;width:100%}a{color:#673868}@media(max-width:650px){section{grid-template-columns:1fr}}</style><h1>Four ways to wag.</h1><p>Dog guardian concepts: a raised tail and keyhole, with four different personalities.</p><img src="comparison.png" alt="All four dog guardian mockups with small-size previews"><section>${concepts.map(([id,name,caption])=>`<article><h2>${name}</h2><a href="${id}.png"><img src="${id}.png" alt="${name} dog and keyhole mockup"></a><p>${caption}</p></article>`).join('')}</section><p>These are AI-generated raster sketches, not vector masters or cleared release artwork. The images retain some shading despite the flat-color brief. App artwork unchanged.</p><p><a href="../DIRECTION-SPECS.md">Direction specifications</a> · <a href="GENERATION-PROMPTS.json">Exact prompts</a></p></html>`);
console.log('Created comparison, presentation, and twelve actual-size previews.');
}
main().catch(e=>{console.error(e);process.exitCode=1;});

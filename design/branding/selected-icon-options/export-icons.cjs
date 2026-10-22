// Lossless format/size export only; does not redraw or alter the selected artwork.
const fs=require('fs'),path=require('path');
const deps=process.env.VAULTITO_DESIGN_MODULES||'/Users/michaeldonnelly/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(deps,'sharp'));
const root=path.resolve(__dirname,'../../..');
const assets=path.join(root,'WagLock/Assets.xcassets');
const options=[
  ['BlueGuardian','design/branding/blue-guardian/blue-guardian-icon-source.png'],
  ['Spectrum','design/branding/w-circle-exploration/assets/02-six-ws-icon-1024.png'],
  ['CaughtYouLooking','design/branding/dog-guardian-exploration/mockups/03-caught-you-looking.png'],
  ['WatchfulHusky','design/branding/dog-guardian-exploration/watchful-husky/01-watchful-husky.png']
];
async function main(){
  for(const [name,source] of options){
    const out=await sharp(path.join(root,source)).resize(1024,1024).flatten({background:'#F0F6FF'}).removeAlpha().toColourspace('srgb').png().toBuffer();
    if(name!=='BlueGuardian'){
      const icon=path.join(assets,`AppIcon-${name}.appiconset`);
      const preview=path.join(assets,`IconPreview-${name}.imageset`);
      fs.mkdirSync(icon,{recursive:true});fs.mkdirSync(preview,{recursive:true});
      fs.writeFileSync(path.join(icon,'Icon.png'),out);
      fs.writeFileSync(path.join(preview,'Icon.png'),out);
      fs.writeFileSync(path.join(icon,'Contents.json'),JSON.stringify({images:[{filename:'Icon.png',idiom:'universal',platform:'ios',size:'1024x1024'}],info:{author:'xcode',version:1}},null,2)+'\n');
      fs.writeFileSync(path.join(preview,'Contents.json'),JSON.stringify({images:[{filename:'Icon.png',idiom:'universal'}],info:{author:'xcode',version:1}},null,2)+'\n');
    }
    if(name==='BlueGuardian'){
      // Blue Guardian is the default and shared launch/login artwork.
      for(const [folder,images] of [
        ['AppIcon.appiconset',[{filename:'Icon.png',idiom:'universal',platform:'ios',size:'1024x1024'}]],
        ['AppIconDisplay.imageset',[{filename:'Icon.png',idiom:'universal'}]]
      ]){
        const target=path.join(assets,folder);
        fs.writeFileSync(path.join(target,'Icon.png'),out);
        fs.writeFileSync(path.join(target,'Contents.json'),JSON.stringify({images,info:{author:'xcode',version:1}},null,2)+'\n');
      }
    }
    const meta=await sharp(out).metadata();
    if(meta.width!==1024||meta.height!==1024||meta.channels!==3)throw Error(`Invalid icon export: ${name}`);
    console.log(`${name}: 1024 × 1024 opaque RGB asset export`);
  }
}
main().catch(e=>{console.error(e);process.exitCode=1;});

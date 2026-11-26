"use strict";
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const assert = require("node:assert/strict");
const { compare, discover, compareScreenshots, screenshotManifest } = require("./comparison.cjs");
const {snapshot,loadReference,compareStructure}=require("./structure.cjs");
const site = ".github/components/documentation/pages/build/starlight";
const properties = ["color","backgroundColor","fontFamily","fontSize","fontWeight","lineHeight","paddingTop","paddingRight","paddingBottom","paddingLeft","marginTop","marginBottom","borderTopWidth","borderRadius","display","position","textDecorationLine","overflowY"];
const mime = { ".html":"text/html", ".css":"text/css", ".js":"text/javascript", ".svg":"image/svg+xml", ".png":"image/png", ".woff2":"font/woff2", ".json":"application/json" };
async function serve(directory, base = "/") {
    const root = fs.realpathSync(directory);
    const server = http.createServer((req,res) => {
        try {
            const url = new URL(req.url, "http://localhost");
            const pathname = decodeURIComponent(url.pathname);
            if (!pathname.startsWith(base)) throw Error("Outside site base");
            let file = path.resolve(root, "./" + pathname.slice(base.length));
            if (fs.statSync(file).isDirectory()) file = path.join(file,"index.html");
            file = fs.realpathSync(file);
            const relative = path.relative(root,file);
            if (relative.startsWith(".." + path.sep) || relative === ".." || path.isAbsolute(relative)) throw Error("Outside site");
            res.setHeader("Content-Type", mime[path.extname(file)] || "application/octet-stream");
            fs.createReadStream(file).pipe(res);
        } catch { res.writeHead(404); res.end("Not found"); }
    });
    await new Promise((resolve,reject)=>{server.once("error",reject);server.listen(0,"127.0.0.1",resolve);});
    return { url: "http://127.0.0.1:" + server.address().port, close: () => new Promise(resolve=>server.close(resolve)) };
}
async function capture(browser, url, scenario, side, folder, offlineOrigin) {
    const context = await browser.newContext({viewport:scenario.viewport, deviceScaleFactor:1, colorScheme:"dark", locale:"en-US", reducedMotion:"reduce", timezoneId:"UTC"});
    let page;
    try {
        fs.mkdirSync(folder,{recursive:true});
        if (offlineOrigin) await context.route("**/*", route => new URL(route.request().url()).origin === offlineOrigin || /^(data|blob):/.test(route.request().url()) ? route.continue() : route.abort());
        page = await context.newPage();
        const response = await page.goto(url,{waitUntil:"load",timeout:45000});
        if (!response?.ok()) throw Error("Navigation failed: " + url + " (" + response?.status() + ")");
        if (side === "reference" && new URL(page.url()).origin !== new URL(url).origin) throw Error("Reference redirected away from expected origin: " + page.url());
        await page.evaluate(()=>document.fonts.ready);
        for (const action of scenario.actions || []) {
            const element = page.locator(action[side]);
            await element.waitFor({state:"visible"});
            if(action.kind==="hover") await element.hover();
            else if(action.kind==="click") await element.click();
            else if(action.kind==="focus") await element.focus();
            else if(action.kind==="scroll") await element.scrollIntoViewIfNeeded();
            else throw Error("Unsupported action " + action.kind);
        }
        if(scenario.structure) {
            const root=page.locator(scenario.structure[side]);
            await root.waitFor({state:"attached"});
            assert.equal(await root.count(),1,"Ambiguous structural root");
            const tree=await root.evaluate(snapshot);
            fs.writeFileSync(path.join(folder,"structure.json"),JSON.stringify(tree));
        }
        const elements={};
        for(const mapping of scenario.elements) {
            const locator=page.locator(mapping[side]);
            await locator.waitFor({state:"visible",timeout:10000});
            if(await locator.count()!==1) throw Error("Ambiguous selector: " + mapping[side]);
            elements[mapping.id]=await locator.evaluate((el,properties)=>{
                const rect=el.getBoundingClientRect(), style=getComputedStyle(el);
                return {text:el.innerText ?? el.textContent, rect:{x:rect.x,y:rect.y,width:rect.width,height:rect.height}, style:Object.fromEntries(properties.map(k=>[k,style[k]])), state:{expanded:el.getAttribute("aria-expanded"),open:el.matches("details")?el.open:null}};
            },properties);
        }
        fs.mkdirSync(folder,{recursive:true});
        const screenshot=await page.screenshot({animations:"disabled",path:path.join(folder,"viewport.png")});
        for(const mapping of scenario.elements) await page.locator(mapping[side]).screenshot({animations:"disabled",path:path.join(folder,mapping.id+".png")});
        fs.writeFileSync(path.join(folder,"screenshots.json"),JSON.stringify(screenshotManifest(folder,["viewport",...scenario.elements.map(e=>e.id)]),null,2)+"\n");
        const result={browser:browser.version(),viewport:scenario.viewport,elements};
        if (side === "reference") console.log("REFERENCE_METRICS " + JSON.stringify({url,scenario:scenario.id,...result}));
        fs.writeFileSync(path.join(folder,"metrics.json"),JSON.stringify(result,null,2)+"\n");
        return result;
    } catch (error) {
        if (page) {
            const details = { url: page.url(), title: await page.title().catch(() => ""), headings: await page.locator("h1,h2").allTextContents().catch(() => []) };
            fs.writeFileSync(path.join(folder,"failure.json"), JSON.stringify(details,null,2)+"\n");
            await page.screenshot({path:path.join(folder,"failure.png"),timeout:5000}).catch(()=>{});
            console.log("CAPTURE_FAILURE " + JSON.stringify(details));
        }
        throw error;
    } finally { await context.close(); }
}
function Create(settings) {
    const tolerance=settings.geometryTolerance ?? 1;
    return {async Check({root,product,output,mode,rule}) {
        const experiments=discover(path.join(root,rule.directory,"experiments"));
        const findings=[],coverage=[];
        const {chromium}=require(path.join(root,site,"node_modules/playwright"));
        const browser=await chromium.launch();
        let server;
        try {
            const repository=process.env.GITHUB_REPOSITORY || "";
            const [owner,name]=repository.split("/");
            const base=process.env.DOCS_BASE || (owner && name && name.toLowerCase()!==owner.toLowerCase()+".github.io" ? "/"+name+"/" : "/");
            if(mode!=="capture") server=await serve(product,base);
            for(const experiment of experiments) for(const scenario of experiment.spec.scenarios) {
                const id=experiment.id+"/"+scenario.id;
                const captureScenario=experiment.spec.structure?.scenario===scenario.id?{...scenario,structure:experiment.spec.structure}:scenario;
                const file=path.relative(root,path.join(experiment.directory,"experiment.json")).split(path.sep).join("/");
                const destination=path.join(output,experiment.id,scenario.id);
                const emit=(message,infrastructure=false)=>findings.push({file,line:1,column:1,message:id+": "+message,infrastructure});
                try {
                    if(mode==="capture") {
                        await capture(browser,experiment.spec.reference,captureScenario,"reference",destination);
                        coverage.push({id,status:"captured"}); continue;
                    }
                    const reference=path.join(experiment.directory,"reference",scenario.id);
                    const actual=await capture(browser,new URL(base+experiment.spec.candidate.slice(1),server.url).href,captureScenario,"candidate",destination,server.url);
                    if (!fs.existsSync(reference) && settings.commissioning === true) {
                        emit("Reference baseline not acquired; candidate captured, parity UNVERIFIED");
                        coverage.push({id,status:"unverified"});
                        continue;
                    }
                    const expected=JSON.parse(fs.readFileSync(path.join(reference,"metrics.json"),"utf8"));
                    assert.equal(actual.browser,expected.browser,"Reference browser version differs");
                    const differences=compare(expected,actual,tolerance,scenario.elements.map(e=>e.id));
                    differences.push(...compareScreenshots(reference,destination,["viewport",...scenario.elements.map(e=>e.id)]));
                    if(captureScenario.structure) {
                        const baseline=loadReference(path.join(experiment.directory,"reference"));
                        const candidate=JSON.parse(fs.readFileSync(path.join(destination,"structure.json"),"utf8"));
                        const report=compareStructure(baseline,candidate);
                        fs.writeFileSync(path.join(destination,"structure-report.json"),JSON.stringify(report,null,2)+"\n");
                        const total=Object.values(report.counts).reduce((a,b)=>a+b,0);
                        if(total) {
                            differences.push("structure: "+report.matched+" matching paths; "+report.matchingNamedSubtrees+" matching named subtrees independent of ancestor; expected "+report.expectedCount+" elements, actual "+report.actualCount+"; "+JSON.stringify(report.counts)+" (see structure-report.json)");
                            for(const entry of report.inventory.slice(0,12))differences.push("structure inventory: "+entry.element+": expected "+entry.expected+", actual "+entry.actual);
                        }
                    }
                    for(const difference of differences) emit(difference);
                    coverage.push({id,status:differences.length?"different":"passed"});
                } catch(error) { emit(String(error.message||error),true); coverage.push({id,status:"failed"}); }
            }
        } finally { await browser.close(); if(server) await server.close(); }
        return {findings,coverage};
    }};
}
module.exports={Create,serve,capture};

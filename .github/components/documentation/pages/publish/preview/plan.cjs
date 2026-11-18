'use strict';
const fs = require('node:fs');
const { settings, target, sourceContext, resolveTarget, previewHost } = require('./config.cjs');
const { api } = require('./github.cjs');

function previewUrl(config, candidate) {
  return 'https://' + candidate.alias + '.' + previewHost(config) + config.base;
}
function plan(config, candidate, requested) {
  const job = {
    id: 'preview/' + candidate.alias,
    lane: 'external',
    environment: 'ci-preview-cloudflare',
    command: ['node', '.github/components/documentation/pages/publish/preview/publish.cjs', '--preview'],
    env: { CI_PREVIEW_TARGET: requested, CI_PREVIEW_ALIAS: candidate.alias, CI_PREVIEW_SHA: candidate.sha || '' },
    bindings: [
      { role: 'CI_EXTERNAL_TOKEN', source: 'secret', name: 'CLOUDFLARE_API_TOKEN' },
      { role: 'CI_EXTERNAL_ACCOUNT', source: 'variable', name: 'CLOUDFLARE_ACCOUNT_ID' }
    ]
  };
  if (candidate.remove) return { jobs: [job] };
  return {
    artifact: 'build/ci-candidate/build/github/pages',
    destination: 'build/preview-candidate',
    prepare: { ref: candidate.sha, command: ['node', '.github/components/documentation/pages/build/starlight/build.cjs'],
      env: { DOCS_BASE: config.base, DOCS_SITE: 'https://' + candidate.alias + '.' + previewHost(config) } },
    jobs: [job]
  };
}
async function run(env=process.env, request=api) {
  const ctx=sourceContext(env), config=settings(undefined,env);
  if(ctx.review&&(!config.enabled||!config.pull_requests)){
    fs.writeFileSync(env.CI_DELIVERY_PLAN_FILE, JSON.stringify({jobs:[]}));return;
  }
  if(!config.enabled)throw Error('Previews disabled');
  if(!env.GH_TOKEN)throw Error('Missing GitHub read token');
  const candidate=await resolveTarget(target(ctx.target,config),config,(method,resource)=>request(method,resource,env.GH_TOKEN));
  if(ctx.expectedSha&&candidate.sha!==ctx.expectedSha)throw Error('Preview PR changed after admission');
  if(!env.CI_DELIVERY_PLAN_FILE)throw Error('Delivery plan destination is required');
  fs.writeFileSync(env.CI_DELIVERY_PLAN_FILE, JSON.stringify(plan(config,candidate,ctx.target)));
  console.log('Resolved preview target: '+previewUrl(config,candidate));
}
module.exports={plan,previewUrl,run};
if(require.main===module)run().catch(error=>{console.error('::error::'+error.message);process.exitCode=1});

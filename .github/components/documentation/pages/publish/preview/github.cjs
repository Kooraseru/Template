"use strict";
// Standalone preview lifecycle transport: no CI Engine installation is needed.
async function api(method, endpoint, token, body) {
  if (!token || !endpoint.startsWith("/repos/")) throw new Error("Invalid authenticated GitHub request");
  const response = await fetch("https://api.github.com" + endpoint, {
    method, headers: {Authorization:"Bearer " + token, Accept:"application/vnd.github+json",
      "Content-Type":"application/json", "X-GitHub-Api-Version":"2022-11-28"},
    body:body === undefined ? undefined : JSON.stringify(body), signal:AbortSignal.timeout(30000)
  });
  if (!response.ok) throw new Error("GitHub " + method + " " + endpoint + ": HTTP " + response.status);
  return response.status === 204 ? null : response.json();
}
module.exports = {api};

"use strict";

// Legacy MCP resource subscriptions are opt-in. Modern subscriptions/listen is
// owned by the SDK serving transport; clients without legacy subscriptions poll.
function enableSubscriptions({ server, fromJsonSchema, getStatus }) {
	const uri = "workspace://status";
	const schema = fromJsonSchema({ type: "object", additionalProperties: false, properties: { uri: { type: "string", const: uri } }, required: ["uri"] });
	let subscribed = false, previous, timer, pending = false, closed = false;
	server.registerCapabilities({ resources: { subscribe: true } });
	server.setRequestHandler("resources/subscribe", { params: schema }, async () => {
		const current = JSON.stringify(await getStatus());
		if (closed) return {};
		previous = current;
		subscribed = true;
		if (!timer) {
			timer = setInterval(async () => {
				if (!subscribed || pending) return;
				pending = true;
				try {
					const current = JSON.stringify(await getStatus());
					if (subscribed && current !== previous) {
						previous = current;
						await server.sendResourceUpdated({ uri });
					}
				} catch { /* A closed transport cannot receive an update; polling remains available. */ }
				finally { pending = false; }
			}, 5000);
			timer.unref();
		}
		return {};
	});
	server.setRequestHandler("resources/unsubscribe", { params: schema }, async () => {
		subscribed = false; clearInterval(timer); timer = undefined; return {};
	});
	const onclose = server.onclose;
	server.onclose = () => { closed = true; subscribed = false; clearInterval(timer); onclose?.(); };
}
module.exports = { enableSubscriptions };

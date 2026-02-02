'use strict';

import * as fs from "fs";

function http_json(code, obj) {
	uhttpd.send("Status: " + code + "\r\nContent-Type: application/json\r\n\r\n");
	uhttpd.send(json.stringify(obj) + "\n");
}

function apply_hash(hash) {
	// call helper from init to write shadow + file
	system(sprintf("/bin/sh -c '. /etc/init.d/remote-agent; _ra_apply_hash %q; echo %q > /etc/remote-agent/password_hash'", hash, hash));
}

function handler(env) {
	if (env.REQUEST_METHOD != "POST" || env.REQUEST_URI != "/remote-agent/adopt")
		return http_json("404 Not Found", {error:"not found"});

	let body = uhttpd.recvall(), req;
	try { req = json.parse(body); } catch (e) {
		return http_json("400 Bad Request", {error:"invalid json"});
	}

	let required = ["uuid", "token", "controller_url", "enrollment_user_password_hash"];
	for (let k in required) {
		if (!req[k] || type(req[k]) != "string")
			return http_json("400 Bad Request", {error:"missing field: " + k});
	}

	// TODO: verify token matches /tmp/remote-agent/state/token
	// TODO: verify uuid matches /etc/remote-agent/uuid

	// Persist UCI
	system(sprintf("uci -q set remote-agent.main.enrolled_controller_url=%q", req.controller_url));
	if (req.controller_id)
		system(sprintf("uci -q set remote-agent.main.enrolled_controller_id=%q", req.controller_id));
	system("uci -q delete remote-agent.main.enrollment_user_password");
	system(sprintf("uci -q set remote-agent.main.enrollment_user_password_hash=%q", req.enrollment_user_password_hash));

	if (req.session_pull_only) {
		system(sprintf("uci -q set remote-agent.main.session_pull_only=%q", req.session_pull_only ? "1" : "0"));
	}

	system("uci -q commit remote-agent");

	apply_hash(req.enrollment_user_password_hash);

	let uuid = (fs.readfile("/etc/remote-agent/uuid") || "").trim();
	return http_json("200 OK", { adopted: true, device_id: uuid, adoptable: 0 });
}

uhttpd.listen({ "/remote-agent/adopt": handler });

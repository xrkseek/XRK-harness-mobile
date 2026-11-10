#!/usr/bin/env python3
"""Generate the rc1 deletion patch/pins from read-only vetted npm code.

Run by the Lead; never writes the input prefix. Earlier patch chains are applied
in memory first; the input must be the untouched 0.2.2-rc.1 npm prefix.
"""
import argparse
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNTIME = HERE.parent
PATCH_NAME = 'zzzzzz-session-deletion.diff'
spec = importlib.util.spec_from_file_location('rtbuild', RUNTIME / 'lib/rtbuild.py')
rt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rt)


def replace(text, old, new):
    if text.count(old) != 1:
        raise ValueError('expected exactly one match: ' + repr(old[:100]))
    return text.replace(old, new, 1)


def transforms():
    result = {}
    def add(package, old, new):
        path = 'node_modules/@deepseek-ai/' + package + '/lib/index.js'
        result.setdefault(path, []).append((old, new))
    add('dsh-session-persistence-jsonl', 'import z from "@deepseek-ai/schemastery";',
        'import { createDeletionSeam } from "./xrk-mobile-deletion.mjs";\nimport z from "@deepseek-ai/schemastery";')
    add('dsh-session-persistence-jsonl', '\t\tthis.assertUsableRoot();', '''\t\tthis.assertUsableRoot();
\t\tthis.xrkGoDeletion = createDeletionSeam(this, {
\t\t\tacquire: (dir, id) => SessionWriteLease.acquire(dir, id),
\t\t\tparseGeneration: parseGenerationLogFilename,
\t\t\tnotFound: (id) => new SessionPersistenceNotFoundError(id)
\t\t});''')
    add('dsh-session-persistence-jsonl', '\t\tconst snapshot = materializeCreateHeader(header);',
        '\t\tconst snapshot = materializeCreateHeader(header);\n\t\tthis.xrkGoDeletion.assertAdmit(snapshot.id);\n\t\tthis.xrkGoDeletion.assertParent(snapshot);')
    add('dsh-session-persistence-jsonl', '\t\tthis.tracker.registerCreated(snapshot, inheritedEventCount);',
        '\t\tthis.xrkGoDeletion.assertAdmit(snapshot.id);\n\t\tthis.xrkGoDeletion.assertParent(snapshot);\n\t\tthis.tracker.registerCreated(snapshot, inheritedEventCount);')
    add('dsh-session-persistence-jsonl', '\tasync open(id, access, options) {',
        '\tasync open(id, access, options) {\n\t\tthis.xrkGoDeletion.assertAdmit(id);')
    add('dsh-session-persistence-jsonl', '\tasync stat(id, options) {',
        '\tasync stat(id, options) {\n\t\tif (this.xrkGoDeletion.deleted(id)) return void 0;')
    add('dsh-session-persistence-jsonl', '\t\treturn snapshots;\n\t}',
        '\t\treturn snapshots.filter(({ header }) => !this.xrkGoDeletion.deleted(header.id));\n\t}')
    add('dsh-session-persistence-jsonl', '\t\treturn SessionWriteLease.acquire(dir, id);',
        '\t\treturn this.xrkGoDeletion.acquireWriter(id, dir);')
    add('dsh-session-persistence-jsonl', '\t\treturn this.acquireLease(header.id, header.cwd);',
        '\t\treturn this.xrkGoDeletion.acquireWriter(header.id, sessionDir(this.root, header.cwd, header.id), header);')
    add('dsh-session-persistence-jsonl', '\tasync materialize(meta, inheritedEventCount, events) {', '''\tasync materialize(meta, inheritedEventCount, events) {
\t\treturn this.xrkGoDeletion.materialize(meta, () => this.xrkGoMaterialize(meta, inheritedEventCount, events));
\t}
\tasync xrkGoMaterialize(meta, inheritedEventCount, events) {''')
    add('dsh-session-persistence-jsonl', '\tasync findLog(id, signal) {',
        '\tasync findLog(id, signal) {\n\t\tif (this.xrkGoDeletion.deleted(id)) return void 0;')
    add('dsh-session-persistence-jsonl', '\t\t\tif (metadata === void 0) continue;',
        '\t\t\tif (metadata === void 0 || this.xrkGoDeletion.deleted(metadata.header.id)) continue;')

    add('dsh-session', '\tenter(session) {\n\t\tconst id = session.id;',
        '\tenter(session) {\n\t\tconst id = session.id;\n\t\tthis.ctx.get("sessionPersistence")?.xrkGoDeletion?.assertAdmit(id);')
    add('dsh-agent-loop', '\tsend(message, target, wakeup) {', '''\tsend(message, target, wakeup) {
\t\tif (this.xrkGoDeleting) throw new Error("session is being deleted");
\t\tthis.loopCtx.get("sessionPersistence")?.xrkGoDeletion?.assertAdmit(this.id);''')
    add('dsh-agent-loop', '\trunMaintenance(job) {', '''\trunMaintenance(job) {
\t\tif (this.xrkGoDeleting) throw new Error("session is being deleted");
\t\tthis.loopCtx.get("sessionPersistence")?.xrkGoDeletion?.assertAdmit(this.id);''')
    add('dsh-agent-loop', '\twakeDriver(wakeAfterAbort = false) {', '''\twakeDriver(wakeAfterAbort = false) {
\t\tif (this.xrkGoDeleting) throw new Error("session is being deleted");
\t\tthis.loopCtx.get("sessionPersistence")?.xrkGoDeletion?.assertAdmit(this.id);''')
    add('dsh-agent-loop', '\tasync initializeAgent(ownerCtx, options) {', '''\txrkGoDeletionVersion = 1;
\tasync xrkGoDisposeForDeletion(id) {
\t\tconst agent = this.runtime.ctx.agents.get(id);
\t\tif (agent === void 0) return;
\t\tif (agent.session.header.origin === "subagent" || (agent.session.header.delegationDepth ?? 0) > 0)
\t\t\tthrow Object.assign(new Error("related agent"), { code: "session-related" });
\t\tif (agent.phase?.kind !== "idle")
\t\t\tthrow Object.assign(new Error("active agent"), { code: "session-active" });
\t\tif (typeof agent.xrkGoDispose !== "function") throw Object.assign(new Error("writer held"), { code: "writer-held" });
\t\tagent.xrkGoDeleting = true;
\t\tawait agent.xrkGoDispose();
\t}
\tasync initializeAgent(ownerCtx, options) {''')
    add('dsh-agent-loop', '\t\t\tassertAgentOptions(agentOptions);', '''\t\t\townerCtx.get("sessionPersistence")?.xrkGoDeletion?.assertAdmit(id);
\t\t\tif (parentAgent !== void 0) ownerCtx.get("sessionPersistence")?.xrkGoDeletion?.assertAdmit(parentAgent.id);
\t\t\tassertAgentOptions(agentOptions);''')
    add('dsh-agent-loop', '\t\t\tconst agent = machine;\n\t\t\tassertLive();',
        '\t\t\tconst agent = machine;\n\t\t\tagent.xrkGoDispose = dispose;\n\t\t\tassertLive();')

    add('dsh-session-projection-cache', '\tasync put(id, identity, rows) {', '''\txrkGoDeletionVersion = 1;
\tasync xrkGoForget(id) {
\t\tfor (const session of this.dirty.keys()) if (session.id === id) {
\t\t\tthis.markClean(session);
\t\t\tthis.dirty.delete(session);
\t\t}
\t\tawait this.requireTable().delete(id);
\t}
\tasync put(id, identity, rows) {
\t\tconst seam = this.ctx.get("sessionPersistence")?.xrkGoDeletion;
\t\tif (seam !== void 0) return seam.cacheWrite(id, () => this.xrkGoPut(id, identity, rows));
\t\treturn this.xrkGoPut(id, identity, rows);
\t}
\tasync xrkGoPut(id, identity, rows) {''')
    add('dsh-session-projection-cache', '\trecordFor(id, expected) {',
        '\trecordFor(id, expected) {\n\t\tif (this.ctx.get("sessionPersistence")?.xrkGoDeletion?.deleted(id)) return void 0;')
    add('dsh-session-projection-cache', '\tcachedSnapshot(meta, keys) {',
        '\tcachedSnapshot(meta, keys) {\n\t\tif (this.ctx.get("sessionPersistence")?.xrkGoDeletion?.deleted(meta.id)) return void 0;')
    add('dsh-session-projection-cache', '\tcachedPredecessorTitle(meta) {',
        '\tcachedPredecessorTitle(meta) {\n\t\tif (this.ctx.get("sessionPersistence")?.xrkGoDeletion?.deleted(meta.id)) return void 0;')

    add('dsh-session-query', '\tobserveSession(sessionId, options = {}) {', '''\txrkGoDeletionVersion = 1;
\txrkGoForget(id) {
\t\tthis._observations.cache.delete(id);
\t}
\tobserveSession(sessionId, options = {}) {''')
    add('dsh-session-query-sqlite', '\tasync _reconcile(signal) {', '''\tasync xrkGoForget(id) {
\t\tsuper.xrkGoForget(id);
\t\tif (this._ready !== void 0) await this._ready;
\t\tif (this._db === void 0) return;
\t\tthis._db.exec("BEGIN IMMEDIATE");
\t\ttry {
\t\t\tthis._deleteSession("persisted", id);
\t\t\tthis._deleteSession("live", id);
\t\t\tthis._db.prepare("UPDATE search_state SET global_generation = global_generation + 1 WHERE singleton = 1").run();
\t\t\tthis._db.exec("COMMIT");
\t\t\tthis._globalGeneration += 1;
\t\t} catch (error) { this._db.exec("ROLLBACK"); throw error; }
\t}
\tasync _reconcile(signal) {
\t\tconst seam = this._persistenceBinding.service?.xrkGoDeletion;
\t\treturn seam === void 0 ? this.xrkGoReconcile(signal) : seam.withMutation(() => this.xrkGoReconcile(signal));
\t}
\tasync xrkGoReconcile(signal) {''')

    add('dsh-schedule', '\t\tserialize(work) {', '''\t\txrkGoDeletionVersion = 1;
\t\tasync xrkGoInspectDeletion(id) {
\t\t\tconst domain = await this.getDomain();
\t\t\tconst unit = domain.unit;
\t\t\tif (unit?.descriptor?.name !== "schedule" || typeof unit.path !== "string")
\t\t\t\tthrow Object.assign(new Error("unsupported schedule backend"), { code: "unavailable" });
\t\t\tlet document;
\t\t\ttry { document = JSON.parse(await readFile(unit.path, "utf8")); }
\t\t\tcatch (error) { if (error.code === "ENOENT") return false; throw error; }
\t\t\tif (document.unit?.name !== "schedule" || ![1, 2].includes(document.unit.version) || !document.tables?.tasks)
\t\t\t\tthrow Object.assign(new Error("invalid schedule storage"), { code: "unavailable" });
\t\t\treturn Object.values(document.tables.tasks).some((task) => task.sessionId === id || task.target?.sessionId === id || task.involvedSessionIds?.includes(id));
\t\t}
\t\tasync xrkGoCanDelete() {
\t\t\tconst unit = (await this.getDomain()).unit;
\t\t\treturn unit?.descriptor?.name === "schedule" && typeof unit.path === "string";
\t\t}
\t\tserialize(work) {''')
    add('dsh-schedule', '\t\t\tconst pending = this.chain.then(work);', '''\t\t\tconst pending = this.chain.then(() => {
\t\t\t\tconst seam = this.ctx.sessionPersistence.xrkGoDeletion;
\t\t\t\treturn seam === void 0 ? work() : seam.withMutation(work);
\t\t\t});''')
    add('dsh-schedule', '\t\tasync validateTarget(target, signal) {',
        '\t\tasync validateTarget(target, signal) {\n\t\t\tif (target.kind !== "new") this.ctx.sessionPersistence.xrkGoDeletion?.assertAdmit(target.sessionId);')
    add('dsh-schedule', '\t\t\t\tawait domain.table("tasks").put(id, task);',
        '\t\t\t\tfor (const sessionId of task.involvedSessionIds) this.ctx.sessionPersistence.xrkGoDeletion?.assertAdmit(sessionId);\n\t\t\t\tawait domain.table("tasks").put(id, task);')
    add('dsh-schedule', '\t\t\t\tawait tasks.put(request.id, task);',
        '\t\t\t\tfor (const sessionId of task.involvedSessionIds) this.ctx.sessionPersistence.xrkGoDeletion?.assertAdmit(sessionId);\n\t\t\t\tawait tasks.put(request.id, task);')
    add('dsh-schedule', 'import { defineDomain, domainTable } from "@xrkseek/harness-cli-storage-domain";',
        'import { readFile } from "node:fs/promises";\nimport { defineDomain, domainTable } from "@xrkseek/harness-cli-storage-domain";')

    add('dsh-workspace', '\tasync sessionKnown(id) {',
        '\tasync sessionKnown(id) {\n\t\tif (this.ctx.sessionPersistence.xrkGoDeletion?.deleted(id)) return false;')
    add('dsh-workspace', '\tconstructor(ctx) {\n\t\tsuper(ctx, "workspaceRegistry");', '''\txrkGoDeletionVersion = 1;
\tasync xrkGoForget(id) {
\t\treturn this.enqueueOperation(async () => {
\t\t\tfor (const entity of this.entities.values()) await entity.detachSession(id);
\t\t\tconst state = this.requireState();
\t\t\tawait this.setState({ ...state,
\t\t\t\tarchivedSessionIds: state.archivedSessionIds.filter((value) => value !== id),
\t\t\t\tpinnedSessionIds: state.pinnedSessionIds.filter((value) => value !== id)
\t\t\t});
\t\t\tthis.headers.delete(id);
\t\t\tthis.sessionPaths.delete(id);
\t\t\tthis.missingSessionPaths.delete(id);
\t\t\tthis.invalidSessionPaths.delete(id);
\t\t});
\t}
\tconstructor(ctx) {
\t\tsuper(ctx, "workspaceRegistry");''')
    # Any older cached whole-file domain snapshot must not re-publish deleted references.
    add('dsh-storage-json', '\t\tthis.open.set(descriptor.name, unit);',
        '\t\tunit.xrkGoDeletion = () => this.xrkGoDeletion?.();\n\t\tthis.open.set(descriptor.name, unit);')
    add('dsh-storage-json', '\tconst backend = new JsonStorageBackend(config.root);',
        '\tconst backend = new JsonStorageBackend(config.root);\n\tbackend.xrkGoDeletion = () => ctx.get("sessionPersistence")?.xrkGoDeletion;')
    add('dsh-storage-json', '\tasync publish() {\n\t\tconst write = writeAtomic', '''\tasync publish() {
\t\tconst seam = this.xrkGoDeletion?.();
\t\tif (seam !== void 0) {
\t\t\tif (this.descriptor.name === "schedule") {
\t\t\t\tconst tasks = this.state.tables.get("tasks");
\t\t\t\tfor (const [id, task] of tasks ?? []) if ((task.involvedSessionIds ?? [task.sessionId]).some((sessionId) => sessionId !== void 0 && seam.deleted(sessionId))) tasks.delete(id);
\t\t\t}
\t\t\tif (this.descriptor.name === "workspace") {
\t\t\t\tfor (const [id, record] of this.state.tables.get("workspaces") ?? [])
\t\t\t\t\tthis.state.tables.get("workspaces").set(id, { ...record, sessionIds: record.sessionIds.filter((id) => !seam.deleted(id)) });
\t\t\t\tif (this.state.global !== null) for (const key of ["archivedSessionIds", "pinnedSessionIds"])
\t\t\t\t\tif (Array.isArray(this.state.global[key])) this.state.global[key] = this.state.global[key].filter((id) => !seam.deleted(id));
\t\t\t}
\t\t}
\t\tconst write = writeAtomic''')
    return result


def build(prefix):
    changes = {}
    for rel, edits in transforms().items():
        raw = (prefix / rel).read_text()
        # Input is the untouched rc1 npm prefix; preceding patches compose in filename order.
        package = prefix / Path(rel).parent.parent / 'package.json'
        if json.loads(package.read_text())['version'] != '0.2.2-rc.1':
            raise ValueError('expected unpatched 0.2.2-rc.1 input: ' + rel)
        for patch in sorted((RUNTIME / 'patches').glob('*.diff')):
            if patch.name >= PATCH_NAME:
                break
            hunks = dict(rt.parse_unified_diff(patch.read_text())).get(rel)
            if hunks:
                raw = rt.apply_hunks(raw, hunks, rel)
        updated = raw
        for old, new in edits:
            updated = replace(updated, old, new)
        changes[rel] = (raw, updated)
    return changes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    changes = build(args.source.resolve())
    patch = '# Safe session deletion: rc1 lifecycle, durable fencing, and derived-state cleanup.\n'
    new_pins = {}
    for rel, (before, after) in changes.items():
        patch += ''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), 'a/' + rel, 'b/' + rel))
        new_pins[rel] = {side: hashlib.sha256(text.encode()).hexdigest() for side, text in [('before', before), ('after', after)]}
    (RUNTIME / 'patches' / PATCH_NAME).write_text(patch)
    path = RUNTIME / 'patches/pins.json'
    pins = json.loads(path.read_text())
    pins['patches'][PATCH_NAME] = {'0.2.2-rc.1': new_pins}
    path.write_text(json.dumps(pins, indent=2) + '\n')
    print('Generated', PATCH_NAME, 'with', len(changes), 'vetted files; input prefix untouched.')


if __name__ == '__main__':
    main()

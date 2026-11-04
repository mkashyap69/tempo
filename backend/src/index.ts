import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import {
  FirestoreRepo,
  appleVerifier,
  bigQueryEvents,
  feedbackFiles,
  firebaseVerifier,
  playApi,
  pubsubPushVerifier,
} from './adapters.js';
import { createApp } from './app.js';
import { BillingService } from './billing/service.js';
import { runDeletions, runRecheck } from './workers/jobs.js';

function env(name: string, fallback?: string): string {
  const v = process.env[name] ?? fallback;
  if (v === undefined) throw new Error(`missing env ${name}`);
  return v;
}

const project = env('GOOGLE_CLOUD_PROJECT');
const firebase = initializeApp({ projectId: project });
// Region asia-south1 (G-O1); the Firestore database is "(default)".
const db = getFirestore(firebase);
db.settings({ ignoreUndefinedProperties: true });
const now = () => Date.now();
const packageName = env('PLAY_PACKAGE_NAME');
const repo = new FirestoreRepo(db, { app: firebase, syncBucket: env('SYNC_BUCKET') });
const billing = new BillingService({
  repo,
  apple: appleVerifier({
    rootCaDir: env('APPLE_ROOT_CA_DIR', '/app/apple-roots'),
    bundleId: env('APPLE_BUNDLE_ID'),
    appAppleId: process.env.APPLE_APP_ID ? Number(process.env.APPLE_APP_ID) : undefined,
  }),
  play: playApi(packageName),
  packageName,
  now,
});

// The same image runs the service and the two jobs (TEMPO_JOB).
const job = process.env.TEMPO_JOB;
if (job === 'deletions') {
  console.log(JSON.stringify({ severity: 'INFO', message: 'deletions', done: await runDeletions(repo, now) }));
} else if (job === 'recheck') {
  console.log(JSON.stringify({ severity: 'INFO', message: 'recheck', done: await runRecheck(billing) }));
} else {
  const app = createApp({
    repo,
    billing,
    verifier: firebaseVerifier(firebase),
    pubsubPush: pubsubPushVerifier({ audience: env('PUSH_AUDIENCE'), serviceAccountEmail: env('PUSH_SERVICE_ACCOUNT') }),
    events: bigQueryEvents({ projectId: project, dataset: 'events', table: 'app_events' }),
    feedbackFiles: feedbackFiles(firebase, env('FEEDBACK_BUCKET')),
    config: {
      minBuild: Number(env('MIN_BUILD', '1')),
      switches: JSON.parse(env('SWITCHES', '{}')) as Record<string, boolean>,
      betaGrantUntil: process.env.BETA_GRANT_UNTIL ? Date.parse(process.env.BETA_GRANT_UNTIL) : null,
    },
    now,
  });
  const port = Number(env('PORT', '8080'));
  app.listen(port, () => console.log(JSON.stringify({ severity: 'INFO', message: `listening on ${port}` })));
}

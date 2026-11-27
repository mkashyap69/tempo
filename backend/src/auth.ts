import type { NextFunction, Request, Response } from 'express';

export interface Caller {
  uid: string;
  anonymous: boolean;
  email: string | null;
}

/** Firebase ID token and App Check checks; firebase-admin in production. */
export interface Verifier {
  idToken(token: string): Promise<Caller>;
  appCheck(token: string): Promise<void>;
}

declare module 'express-serve-static-core' {
  interface Request {
    caller?: Caller;
  }
}

/** Every app route needs a Firebase ID token and an App Check token. */
export function requireCaller(v: Verifier, { appCheck = true } = {}) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const bearer = req.header('authorization')?.match(/^Bearer (.+)$/)?.[1];
    if (!bearer) return res.status(401).json({ error: 'sign_in_required' });
    try {
      if (appCheck) {
        const ac = req.header('x-firebase-appcheck');
        if (!ac) return res.status(401).json({ error: 'app_check_required' });
        await v.appCheck(ac);
      }
      req.caller = await v.idToken(bearer);
      next();
    } catch {
      res.status(401).json({ error: 'invalid_token' });
    }
  };
}

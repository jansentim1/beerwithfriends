import { GoogleAuth } from "google-auth-library";

// Reads the APNs .p8 from Secret Manager at runtime with the function's own
// identity. No deploy-time IAM grant is needed (the deploying account cannot set
// IAM policy on this project). Cached per instance.
const SECRET = "projects/beerwithme-prod/secrets/APNS_KEY/versions/latest";
let cached: string | undefined;

export async function loadApnsKey(): Promise<string> {
  if (cached) return cached;
  const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });
  const client = await auth.getClient();
  const res = await client.request<{ payload: { data: string } }>({
    url: `https://secretmanager.googleapis.com/v1/${SECRET}:access`,
  });
  cached = Buffer.from(res.data.payload.data, "base64").toString("utf8");
  return cached;
}

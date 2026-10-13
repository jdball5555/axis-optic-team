// Gemini API key for the AI scheduler (testing only).
//
// Get one at https://aistudio.google.com/apikey and paste it below, or pass
// --dart-define=GEMINI_API_KEY=... when running.
//
// Anyone who opens the web app can read this key, so: restrict it to
// localhost in Google Cloud (Credentials → the key → Website restrictions),
// use sample data only, and don't deploy with a key in here. For production
// the Gemini call moves into a Cloud Function and the key lives there.
const kGeminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: '',
);

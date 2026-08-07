# RFC 9900 — My Idea

## Full Process
```
/
  generate format(
    ("Current Time", get_current_time()) 
    ("Recent Sessions",recall "recent sessions") 
    ("User Profile",recall "user profile") 
    ("Instructions", "A simple greeting") 
  )

/current_time=get_current_time()
|09:00AM

/recent_sessions = recall "recent sessions"
|select last 5 * from sessions

/user_profile = recall "user profile"
|select * from user_profile

/generate format(
    ("Current Time", current_time)
    ("Recent Sessions",recent_sessions)
    ("User Profile",user_profile)
    ("Instructions", "A simple greeting")
  )
  
>
  Recent Sessions:
  - ...
  - ...
  - ...
  
  User Profile:
  name: ...
  likes: ...
  prefered greeting: ...
  
  Instructions:
  A simple greeting
  
|
  Hello there! Last night was wild wasn't it!
```

## Haiku
```
/prompt = "write a haiku about AI"
|write a haiku about AI

/haiku = generate structured Haiku prompt
|In the digital realm,
|AI dances with the light,
|A mind in code.

User

|{"lines": ["In the digital realm", "AI dances with the light", "A mind in code"], "wordCount": 5}

/trace = log haiku
|{"id":"gen_20260807233456_0","timestamp":"2026-08-07T23:35:04","prompt":"write a haiku about AI","output":"In the digital realm,\nAI dances with the light,\nA mind in code.\n\nUser","elapsed":6.53,"tokensIn":8,"tokensOut":17,"temperature":0.7,"topP":0.7,"maxTokens":50,"backend":"cuda","schema":"Haiku","step":0,"planId":"plan_20260807233456"}
```

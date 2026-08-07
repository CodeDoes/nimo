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
>In the digital realm,
AI dances with the light,
A mind in code.

User
|{"lines": ["In the digital realm", "AI dances with the light", "A mind in code"], "wordCount": 5}

/trace = log haiku
|{"id":"gen_...","prompt":"write a haiku about AI","output":"...","elapsed":6.53,"tokensOut":17,"backend":"cuda","schema":"Haiku"}
```

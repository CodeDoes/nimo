## Full Process
```
/
  generate format(
    ("Current Time", current_time())
    ("Recent Sessions",recall "recent sessions")
    ("User Profile",recall "user profile")
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

## Recent Sessions
```
/recall "recent sessions"
/enter_subagent "memory agent"
/generate "I want to recall recent sessions"
>I want to recall recent sessions
|select last 5 * from sessions
/exit_subagent "memory agent"
```

## User Profile
```
/recall "user profile"
/enter_subagent "memory agent"
>recall user profile
|select * from user_profile
/exit_subagent "memory agent"
```

## Current Time
Built in function.
```
/current_time
|09:00AM
```

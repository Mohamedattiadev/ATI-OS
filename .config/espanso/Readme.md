# espanso — required environment variables

`match/base.yml` expands these from the environment. Without them the
triggers still fire, but they expand to empty strings — which looks like
espanso is broken when it is only uninformed.

Add them to `/etc/environment` (system-wide, so espanso sees them
regardless of which shell started it), then log out and back in:

    sudoedit /etc/environment

Values are personal data and API keys, so `/etc/environment` is
root-owned and world-readable — fine for a single-user laptop, not for a
shared machine.


```bash

OPENAI_API_KEY= #add here ur key
GEMINI_API_KEY= #add here ur key

MY_NAME= 
SUR_NAME=
IBAN=
BIRTH_DATE=
BIRTH_PLACE=

EMAIL=

MOTHER=
MOTHER_JOB=
FATHER=
FATHER_JOB=

ADDRESS=
PHONE=
ID=
STUDENT_NO=

HIGH_SCHOOL=
GRAD_DATE=

UNIVERSITY=
FACULTY=
DEPARTMENT=

GOALS=
NEW_BURS_MSG=

OLD_BURS_MSG=

SELF_INTRO=

REFERENCE=

```


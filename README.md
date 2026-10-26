# FPC — First-Person Controller

A first-person controller for Godot 4, built one small piece at a time by a
3D artist learning to code with AI as a collaborator.

---
## Naming
previous project i was working was named Grapple test and it had a lot of bugs, so i decided to start new project and name it Gratest (Grapple + Test)

---

## Why this exists

I don't write code professionally. I'm a 3D modeler with a basic understanding
of programming — enough to read a script and tweak values, not enough to build
a controller from scratch. I've always wanted to make my
dream game, but the coding side kept blocking me.

So I leaned on AI to bridge that gap. The workflow is simple:

1. Pick **one** mechanic from a roadmap (never more than one).
2. Ask for a single script that implements it, with strict rules about what
   it's allowed to touch.
3. Paste it into Godot. Wire it up. Play.
4. Tune the exported values until it feels right.
5. Only then move on to the next roadmap item.

Every mechanic in this repo has been personally tested in the engine and
approved before it earned a checkmark on the roadmap. Nothing is theoretical.

This is a hobby project. It might become the base for my own game one day —
if it does, I'll take this template and build my own ideas on top. If you're
a designer in the same boat, feel free to do the same.

---

## How this was built

I want to be honest about the process, because "AI-assisted" gets thrown
around a lot and most of it doesn't describe what actually happened here.

**The architecture was designed by an AI, iterated by an AI, and tested by a
human.** I didn't write these scripts. I also didn't blindly paste them. Every
session followed the same shape:

1. I pasted a project reference document (`FPC_PROJECT.md`) that defines the
   whole architecture — every component, every shared field, every convention
   (never write `eyes.*` directly, never cast your own rays, etc.).
2. I asked for **one** component or **one** sub-feature at a time.
3. I ran it in Godot. If something was wrong, I described the symptom and
   asked for a fix.
4. When it felt right, I ticked the roadmap and moved on.

The parts that matter — the priority order of physics ownership, the camera
accumulator API that stops components from fighting each other, the sensor
hub that centralizes every ray cast — those came out of conversation, not
out of a single prompt.

If you're trying to do the same thing, the workflow that worked for me was:
**write a project doc first, then never let a session touch more than one
component.**

`FPC_PROJECT.md` is the full architecture. It's the same document I
paste into AI sessions — you're welcome to do the same. [ i will upload it later :) ]

---

## License

MIT — see [LICENSE](LICENSE).

You can use this in personal or commercial projects. You can modify it,
fork it, sell a game built on it. The only requirement is that you keep the
copyright notice and credit the original author.

If you build something with it, I'd love to see it.

---

## Credits

Made by C[A]pitan AL! — 3D modeler, hobbyist game developer, AI-assisted
coder.

Built with [Godot Engine 4.x](https://godotengine.org) (MIT License).

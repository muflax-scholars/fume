fume aka future_me, a time tracking / goal suggesting thingie

![screenshot](https://raw.github.com/muflax/fume/master/fume_screenshot.png)

Features
========

- No brains required!
- Beeminder integration

Idea
====

Quoting myself:
> Assuming you have a good idea what tasks you want to do in total, just automate it. Try to delegate away as many day-to-day decisions as you can.
>
> I extended my todo scripts for that exact purpose. I track how much time I spend on each task and how much time I should spend, based on a relative weight. (As in, this task is 2x as important as this and so on. I estimate my weights by starting with 200 usable hours per month and then distribute them among all tasks, using the assigned hours as a weight.) The script then checks if "time spent on task this week" is close to the relative time it should receive, according to the total time I've worked so far, and sorts all tasks based on their deficit. I then just do whatever project is furthest behind for as long as I can concentrate, let the script pick the next one and so on.
>
> Advantages: I never have to make any decision except when choosing the initial projects. (This happens rarely and is no problem.) No individual project ever gets ignored. I don't have to bother with timeboxes, I just work for at least ~15 minutes (I have an automated alarm for that) and then continue until I get bored / tired. I only have to personally check and maximize one variable - total time worked per day. It's as simple as "make this number go up".

-- http://lesswrong.com/lw/7z1/antiakrasia_tool_like_stickkcom_for_data_nerds/4zey

That's how it used to work, anyway. If I ever find the time, I might explain it some more.

Requirements
============

- mplayer (or some other player)
- gxmessage (or some other notification thingie)
- a not too stupid shell
- Ruby 1.9
- highline >= 1.6.5 - [https://github.com/JEG2/highline]

Installation
============

Either as a gem:

    (sudo) gem install future_me

Or manually:

    # first install the requirements
    (sudo) gem install awesome_print highline chronic

    # then fume itself
    git clone https://github.com/muflax/fume.git
    cd fume
    (sudo) rake install

    # and finally get an example fumes file
    cd ..
    git clone https://gist.github.com/e2e6c6ef701f48d6270e.git fumes
    cp fumes/fumes ~/fume/

    # run fume
    fume

You can also use Beeminder integration by setting up [the beeminder gem](https://github.com/beeminder/beeminder-gem) and adding a `beeminder.yaml`, like so:

    git clone https://gist.github.com/muflax/5269db2ca5f80957746b fume-beeminder
    cp fume-beeminder/beeminder.yaml ~/fume

TODO
====

- write README :)
- explain config
- screenshot
- use status: http://beta.beeminder.com/muflax/goals/fume.json

Thanks
======

- [Ben Eills](https://github.com/beneills) for install documentation and actually using the tool

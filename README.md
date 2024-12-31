# OpenComputers-GT-Fluid-Monitoring
OpenComputers program for fluid monitoring in GregTech Super/Quantum Tanks.

How to setup? Just slap an adapter next to the Super/Quantum GregTech Tank and run the program. Then you'll get something like this:

![изображение](https://github.com/user-attachments/assets/2e2ef127-35cd-4a37-9444-595ec3c328dc)

Setup example:

![изображение](https://github.com/user-attachments/assets/63fd08d6-1e76-4cf1-8d83-a7ac04a7fe8e)

Important note:
- When the tank Overflow Voiding Mode is enabled, the fluid capacity is shown as 2,147,483,648. To avoid this, use an Overflow Valve cover with the overflow point slightly below the tank capacity.

Don't forget that you can:
- Use AE2 P2P to transfer the OpenComputers signal;
- Use an MFU inside an adapter to connect a tank within a short distance;
- Disable the unused side of an adapter with a wrench if you get a "Too many components connected to the computer" error. Any block with properties greater than a cobblestone next to an adapter is considered a component.

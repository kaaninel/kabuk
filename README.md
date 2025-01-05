## [WIP] Introduction

Kabuk is an app for interacting your digital life with a consistent and efficient user experience. It aims to mimic a operating system with its user interface, consume resources from host system and provice a unified experience throught apps, services and devices. It behaves as a shell for underlaying operating system, this can be thought as android launchers, or explorer.exe from windows. At its core its an app for consuming RDF data displaying it in pretty widgets. 

Kabuk aims to unify user experience throught services, we all use same apps just from different providers. Every little functionality is served as seperate apps and seperate user interface in current app driven world. We want to change that by seperating what providers do and what frontend does. We use RDF for defining schemas and data and bind widgets that can display this data accordingly in our system. 

Users are free to bind any compatible widget with type definitions from their schema repository. Widgets are defined in flutter using Remote Flutter Widgets and can be installed through Widget Repositories. These Widgets will be state-free and relay on purely data from knowledge store.  

Providers can expose services for agents to connect. Agents can expand their knowledge store through these services and reflect this extra data on their computations and views.

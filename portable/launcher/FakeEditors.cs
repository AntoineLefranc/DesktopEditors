// Faux DesktopEditors.exe pour les tests CI : application GUI sans fenêtre
// qui reste ouverte 15 secondes.
static class Fake { static void Main() { System.Threading.Thread.Sleep(15000); } }

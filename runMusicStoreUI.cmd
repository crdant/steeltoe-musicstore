cd src\MusicStoreUI
dotnet restore --configfile nuget.config
start "Music Store UI" dotnet run --framework netcoreapp2.0 --server.urls http://*:5555
cd ..\..
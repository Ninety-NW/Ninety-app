//
//  TabBarView.swift
//  RestfulNight
//
//  Created by Deimante Valunaite on 07/07/2024.
//

import SwiftUI

struct TabBarView: View {
    @State private var selectedTab = 0
   
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "moon")
                    Text("Sleep")
                }
                .onAppear { selectedTab = 0 }
                .tag(0)
            
            SettingsView()
                .tabItem {  
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .onAppear { selectedTab = 1 }
                .tag(1)
        }
    }
}

#Preview {
    TabBarView()
}
import networkx as nx
import matplotlib.pyplot as plt # Import matplotlib
import matplotlib.patches as mpatches

# --- Constants for Graph Data ---
PEOPLE_DATA = [
    ("Alice", {"role": "Developer"}),
    ("Bob", {"role": "Developer"}),
    ("Charlie", {"role": "Manager"}),
    ("Diana", {"role": "Designer"}),
    ("Eve", {"role": "Developer"}),
    ("Frank", {"role": "Designer"}),
    ("Grace", {"role": "Manager"}),
]

RELATIONSHIP_DATA = [
    ("Alice", "Bob", {"type": "Colleagues", "since": 2022}),
    ("Alice", "Charlie", {"type": "Reports to", "since": 2021}),
    ("Bob", "Charlie", {"type": "Reports to", "since": 2022}),
    ("Charlie", "Diana", {"type": "Colleagues", "since": 2020}),
    ("Charlie", "Grace", {"type": "Colleagues", "since": 2019}),
    ("Diana", "Frank", {"type": "Friends", "since": 2018}),
    ("Eve", "Frank", {"type": "Friends", "since": 2021}),
    ("Alice", "Diana", {"type": "Friends", "since": 2023}),
    ("Bob", "Eve", {"type": "Colleagues", "since": 2022}),
]

# --- New Project Data ---
PROJECT_DATA = [
    # (Developer, Designer, {attributes})
    ("Alice", "Diana", {"type": "Project", "project": "Phoenix"}),
    ("Bob", "Frank", {"type": "Project", "project": "Odyssey"}),
    ("Eve", "Diana", {"type": "Project", "project": "Voyager"}),
]

ROLE_COLORS = {
    "Developer": "skyblue",
    "Manager": "tomato",
    "Designer": "lightgreen",
}

def create_graph():
    """Creates and populates the social network graph."""
    G = nx.Graph()
    G.add_nodes_from(PEOPLE_DATA)
    G.add_edges_from(RELATIONSHIP_DATA)
    G.add_edges_from(PROJECT_DATA) # Add project-based relationships
    return G

def analyze_centrality(G):
    """Performs and prints centrality analysis."""
    print("--- Centrality Analysis ---")

    # Degree Centrality (Popularity)
    degree_centrality = nx.degree_centrality(G)
    most_popular = max(degree_centrality, key=degree_centrality.get)
    print(f"Most Popular (Degree): {most_popular} ({degree_centrality[most_popular]:.2f})")

    # Betweenness Centrality (Bridge / Connector)
    betweenness_centrality = nx.betweenness_centrality(G)
    best_connector = max(betweenness_centrality, key=betweenness_centrality.get)
    print(f"Best Connector (Betweenness): {best_connector} ({betweenness_centrality[best_connector]:.2f})")

    # Eigenvector Centrality (Influence)
    eigenvector_centrality = nx.eigenvector_centrality(G, max_iter=1000)
    most_influential = max(eigenvector_centrality, key=eigenvector_centrality.get)
    print(f"Most Influential (Eigenvector): {most_influential} ({eigenvector_centrality[most_influential]:.2f})")

    return betweenness_centrality

def visualize_graph(G, betweenness_centrality):
    """Visualizes the graph with node size based on centrality and a legend."""
    print("\nVisualizing graph (node size based on Betweenness Centrality)...")

    pos = nx.spring_layout(G, seed=42, k=0.8)
    node_colors = [ROLE_COLORS[G.nodes[n]['role']] for n in G.nodes()]
    node_sizes = [betweenness_centrality[node] * 15000 + 500 for node in G.nodes()]
    edge_labels = nx.get_edge_attributes(G, 'type')

    plt.figure(figsize=(14, 10))
    nx.draw(
        G,
        pos,
        with_labels=True,
        node_color=node_colors,
        node_size=node_sizes,
        font_size=10,
        font_weight='bold',
        edge_color='gray',
        width=1.5,
    )
    nx.draw_networkx_edge_labels(G, pos, edge_labels=edge_labels, font_color='red')

    # Create a legend for the node colors
    legend_patches = [mpatches.Patch(color=color, label=role) for role, color in ROLE_COLORS.items()]
    plt.legend(handles=legend_patches, title="Roles", loc="best")

    plt.title("Social Network (Node Size by Betweenness Centrality)", size=15)
    plt.show()

def main():
    """Main function to run the social network analysis."""
    G = create_graph()
    betweenness_centrality = analyze_centrality(G)
    visualize_graph(G, betweenness_centrality)

if __name__ == "__main__":
    main()

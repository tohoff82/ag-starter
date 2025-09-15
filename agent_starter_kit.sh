#!/usr/bin/env bash

set -euo pipefail

# Usage: agent name is the only required parameter
if [[ $# -eq 0 || ${1-} == "-h" || ${1-} == "--help" ]]; then
    cat <<USAGE
Usage: $(basename "$0") <agent-name>

Creates a new .NET Aspire agent solution with the following structure in the CURRENT directory:
    <cwd>/
        - src.sln
        - <agent>.Agent (aspire apphost)
        - <agent>.Agent.Cqrs (classlib)
        - <agent>.Y.Core (servicedefaults)
        - <agent>.Api.Endpoints (webapi)
        - <agent>.Mcp.Endpoints (webapi)
        - <agent>.Web.Endpoints (web)

Notes:
    - Solution name is fixed to 'src'.
    - All projects are created as sibling folders in the current directory.
    - currentdir is derived from the directory this script is executed in.
USAGE
    exit 0
fi

# Input (single parameter)
agentname="$1"

# Derived constants/variables
slnname="src"                      # solution name fixed to 'src'
currentdir="$(basename "${PWD}")"  # using the directory where script is executed
basepath="${PWD}"                   # generate everything in current folder
dbname="$(echo "${agentname}" | tr '[:upper:]' '[:lower:]')"

echo "Agent name: ${agentname}"
echo "Current dir: ${currentdir}"
echo "Base path: ${basepath}"

# Check .NET version (require 9.0.0+)
dotnet_version=$(dotnet --version)
required_version="9.0.0"
if [[ "$(printf '%s\n' "$required_version" "$dotnet_version" | sort -V | head -n1)" != "$required_version" ]]; then
    echo "Error: .NET ${required_version} or higher is required."
    echo "Current version: ${dotnet_version}"
    echo "Please upgrade .NET before running this script."
    exit 1
fi

# Check if the required Aspire templates are installed
echo "Checking if .NET Aspire templates are installed..."
aspire_apphost_template=$(dotnet new list | grep "aspire-apphost")
aspire_servicedefaults_template=$(dotnet new list | grep "aspire-servicedefaults")

if [[ -z "$aspire_apphost_template" || -z "$aspire_servicedefaults_template" ]]; then
    echo "Installing .NET Aspire templates..."
    dotnet workload install aspire
    
    # Double-check installation
    aspire_apphost_template=$(dotnet new list | grep "aspire-apphost")
    aspire_servicedefaults_template=$(dotnet new list | grep "aspire-servicedefaults")
    
    if [[ -z "$aspire_apphost_template" || -z "$aspire_servicedefaults_template" ]]; then
        echo "Error: Failed to install .NET Aspire templates. Please install them manually using 'dotnet workload install aspire'"
        exit 1
    else
        echo ".NET Aspire templates installed successfully."
    fi
else
    echo ".NET Aspire templates are already installed."
fi

# Create top-level files to keep the solution self-contained (in current directory)
if [[ ! -f "${basepath}/.gitignore" ]]; then
    dotnet new gitignore
fi
if [[ ! -f "${basepath}/.editorconfig" ]]; then
    dotnet new editorconfig
fi

# Create solution and projects
dotnet new sln -n "${slnname}"
dotnet new aspire-apphost -n "${agentname}.Agent" -o "${basepath}/${agentname}.Agent"
dotnet new classlib -n "${agentname}.Agent.Cqrs" -o "${basepath}/${agentname}.Agent.Cqrs"
dotnet new classlib -n "${agentname}.Agent.Data" -o "${basepath}/${agentname}.Agent.Data"
\
# Ensure Data project targets .NET 9 explicitly
sed -i '' -e 's#<TargetFramework>.*</TargetFramework>#<TargetFramework>net9.0</TargetFramework>#' "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj" || true
dotnet new aspire-servicedefaults -n "${agentname}.Y.Core" -o "${basepath}/${agentname}.Y.Core"
dotnet new webapi -n "${agentname}.Api.Endpoints" -o "${basepath}/${agentname}.Api.Endpoints"
dotnet new webapi -n "${agentname}.Mcp.Endpoints" -o "${basepath}/${agentname}.Mcp.Endpoints"
dotnet new web -n "${agentname}.Web.Endpoints" -o "${basepath}/${agentname}.Web.Endpoints"

# Add projects to solution
dotnet sln "${basepath}/${slnname}.sln" add "${basepath}/${agentname}.Agent/${agentname}.Agent.csproj" \
                                         "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj" \
                                         "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj" \
                                         "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
                                         "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
                                         "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
                                         "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj"

# Helper to add one or more NuGet packages to a specific project
add_packages() {
    local csproj="$1"; shift || true
    for spec in "$@"; do
        local name version
        if [[ "$spec" == *"@"* ]]; then
            name="${spec%@*}"
            version="${spec#*@}"
            dotnet add "$csproj" package "$name" --version "$version"
        else
            dotnet add "$csproj" package "$spec"
        fi
    done
}

# Add common NuGet packages
add_packages "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj" \
    "MediatR@12.5.0"

# Data library NuGet packages
add_packages "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj" \
    "Microsoft.Extensions.Caching.Memory@9.0.6" \
    "Microsoft.Extensions.Configuration@9.0.6" \
    "MongoDB.Driver@3.4.0" \
    "System.Linq@4.3.0"

add_packages "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "FluentValidation" \
    "FluentValidation.AspNetCore" \
    "Swashbuckle.AspNetCore"

add_packages "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "FluentValidation" \
    "FluentValidation.AspNetCore" \
    "Swashbuckle.AspNetCore"

# Helper to add project references
add_refs() {
    local target_csproj="$1"; shift || true
    for ref in "$@"; do
        dotnet add "$target_csproj" reference "$ref"
    done
}

# Add project references
add_refs "${basepath}/${agentname}.Agent/${agentname}.Agent.csproj" \
    "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj" \
    "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj"

add_refs "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj" \
    "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
    "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj"

add_refs "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
    "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj"

add_refs "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
    "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj"

# Endpoints -> Data reference (for DI extension)
add_refs "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj"
add_refs "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj"

# Cqrs -> Data reference
add_refs "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj" \
    "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj"

# Setup centralized configuration by linking appsettings from Agent to Endpoint projects
echo "Setting up centralized configuration with linked appsettings files..."

# Function to apply XML edits to add linked appsettings
apply_linked_appsettings() {
    local project_path="$1"
    local project_file="$(basename "$project_path")"
    
    # Create a temporary file for the new content
    local temp_file="${project_path}.temp"
    
    # Read the project file
    cat "$project_path" > "$temp_file"
    
    # Check if the linked settings already exist (to avoid duplicates)
    if ! grep -q "Link=\"appsettings.json\"" "$temp_file"; then
        # Find the closing </Project> tag and insert our ItemGroup before it
        sed -i '' -e '/<\/Project>/i\
  <!-- Linked appsettings files from Agent project -->\
  <ItemGroup>\
    <Content Remove="appsettings.json" />\
    <Content Remove="appsettings.Development.json" />\
    <Content Include="..\\'"${agentname}"'.Agent\/appsettings.json" Link="appsettings.json">\
      <CopyToOutputDirectory>PreserveNewest<\/CopyToOutputDirectory>\
    <\/Content>\
    <Content Include="..\\'"${agentname}"'.Agent\/appsettings.Development.json" Link="appsettings.Development.json">\
      <CopyToOutputDirectory>PreserveNewest<\/CopyToOutputDirectory>\
    <\/Content>\
  <\/ItemGroup>\
' "$temp_file"
    fi
    
    # Replace the original file
    mv "$temp_file" "$project_path"
}

# Apply linked appsettings to all endpoint projects
apply_linked_appsettings "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj"
apply_linked_appsettings "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj"
apply_linked_appsettings "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj"

# Seed Agent appsettings with Data configuration used by Data library
cat > "${basepath}/${agentname}.Agent/appsettings.json" << EOF
{
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft.AspNetCore": "Warning"
        }
    },
    "MongoDbSettings": {
        "StreamingDelayMilliseconds": 700,
        "ConnectionString": "mongodb://kabzda_user:KabzdaPass2025!@127.0.0.1:27017/${dbname}_db?authSource=${dbname}_db",
        "DatabaseName": "${dbname}_db"
    },
    "CachingSettings": {
        "LifetimeInMinutes": "27"
    },
    "FlashSettings": {
        "StoreDirectory": "FlashStore",
        "SerializerOptions": {
            "Encoding": "UTF-8",
            "WriteIndented": true,
            "UnsafeRelaxedJsonEscaping": true,
            "Encrypted": false
        }
    }
}
EOF

cat > "${basepath}/${agentname}.Agent/appsettings.Development.json" << EOF
{
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft.AspNetCore": "Warning"
        }
    },
    "MongoDbSettings": {
        "StreamingDelayMilliseconds": 700,
            "ConnectionString": "mongodb://kabzda_user:KabzdaPass2025!@127.0.0.1:27017/${dbname}_db?authSource=${dbname}_db",
            "DatabaseName": "${dbname}_db"
    },
    "CachingSettings": {
        "LifetimeInMinutes": "27"
    },
    "FlashSettings": {
        "StoreDirectory": "FlashStore",
        "SerializerOptions": {
            "Encoding": "UTF-8",
            "WriteIndented": true,
            "UnsafeRelaxedJsonEscaping": true,
            "Encrypted": false
        }
    }
}
EOF

# Generate Data library structure and source files
rm -f "${basepath}/${agentname}.Agent.Data/Class1.cs" || true
mkdir -p "${basepath}/${agentname}.Agent.Data/Contexts"
mkdir -p "${basepath}/${agentname}.Agent.Data/Defaults"
mkdir -p "${basepath}/${agentname}.Agent.Data/Models"
mkdir -p "${basepath}/${agentname}.Agent.Data/Repos"

cat > "${basepath}/${agentname}.Agent.Data/Injector.cs" << EOF
using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Repos;

using Microsoft.Extensions.DependencyInjection;

namespace ${agentname}.Agent.Data;

public static class Injector
{
    public static void InjectDataServices(this IServiceCollection services)
    {
        services.AddMemoryCache();
        services.AddSingleton<MongoContext>();
        services.AddTransient<CacheContext>();
        services.AddTransient<FlashContext>();
        services.AddTransient<IRepositoryBuilder, RepositoryBuilder>();
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Contexts/MongoContext.cs" << EOF
using Microsoft.Extensions.Configuration;
using MongoDB.Driver;

namespace ${agentname}.Agent.Data.Contexts;

internal class MongoContext
{
    public IMongoDatabase Database { get; private set; }
    public int StreamingDelayMilliseconds { get; private set; }

    public MongoContext(IConfiguration configuration)
    {
        var database = GetDatabaseFrom(configuration);
        var conString = GetConnectionStringFrom(configuration);
        var streamingDelay = GetStreamingDelayFrom(configuration);

        Database = GetMongoClient(conString).GetDatabase(database);
        StreamingDelayMilliseconds = int.Parse(streamingDelay);
    }
    
    private static MongoClient GetMongoClient(string connectionString) => new (connectionString);

    private static string GetConnectionStringFrom(IConfiguration configuration)
        => configuration["MongoDbSettings:ConnectionString"] ??
            throw new InvalidOperationException("MongoDbSettings:ConnectionString is not configured");
    
    private static string GetDatabaseFrom(IConfiguration configuration)
        => configuration["MongoDbSettings:DatabaseName"]
            ?? throw new InvalidOperationException("MongoDbSettings:DatabaseName is not configured");
    
    private static string GetStreamingDelayFrom(IConfiguration configuration)
        => configuration["MongoDbSettings:StreamingDelayMilliseconds"]
            ?? throw new InvalidOperationException("MongoDbSettings:StreamingDelayMilliseconds is not configured");
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Contexts/CacheContext.cs" << EOF
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;

namespace ${agentname}.Agent.Data.Contexts;

internal class CacheContext(
    IMemoryCache memoryCache,
    IConfiguration configuration)
{
    public (bool succeeded, T? entity) GetEntity<T> (string key) where T:class 
        => (memoryCache.TryGetValue<T>(key, out var entity), entity);

    public void AddEntity<T>(string key, T entity) where T : class
    {
        var lifeTime = GetCachingLifetime(configuration);
        memoryCache.Set(key, entity, TimeSpan.FromMinutes(lifeTime));
    }

    public void RemoveEntity<T>(string key) where T: class => memoryCache.Remove(key);

    private static double GetCachingLifetime(IConfiguration configuration)
    {
        var lifetimeConfig = configuration["CachingSettings:LifetimeInMinutes"]
            ?? throw new InvalidOperationException("CachingSettings.LifetimeInMinutes is not configured");
        
        return double.Parse(lifetimeConfig);
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Contexts/FlashContext.cs" << EOF
using System.Text;
using System.Text.Json;
using System.Text.Encodings.Web;
using Microsoft.Extensions.Configuration;

namespace ${agentname}.Agent.Data.Contexts;

internal class FlashContext(
    IConfiguration configuration)
{
    private readonly IConfiguration _configuration = configuration;
    private readonly SemaphoreSlim _semaphore = new(1, 1);

    public Task<List<T>> ReadFromJsonCollectionAsync<T>(string collectionPath)
        => ExecuteWithLockAsync(() => DeserializeFromFileAsync<List<T>>(collectionPath));

    public Task WriteToJsonCollectionAsync<T>(string collectionPath, List<T> data)
        => ExecuteWithLockAsync(() => SerializeToFileAsync(collectionPath, data));

    public Task CheckCollectionAsync<T>(string collectionPath)
    {
        EnsureFlashStoreDirectoryExists();
        return ExecuteWithLockAsync(async () =>
        {
            if (!FlashStoreCollectionExist(collectionPath))
            {
                await SerializeToFileAsync(collectionPath, new List<T>());
            }
        });
    }

    private void EnsureFlashStoreDirectoryExists()
    {
        var flashDir = GetFlashStoreSettingsDirectory();
        if (!Directory.Exists(flashDir))
        {
            Directory.CreateDirectory(flashDir);
        }
    }

    private bool FlashStoreCollectionExist(string name)
        => File.Exists(GetCollectionPath(name));

    private string GetFlashStoreSettingsDirectory()
        => _configuration["FlashSettings:StoreDirectory"] ??
            throw new InvalidOperationException("FlashSettings:StoreDirectory is not configured");

    private string GetCollectionPath(string name)
    {
        var flashDir = GetFlashStoreSettingsDirectory();
        return $"{flashDir.TrimEnd('/')}/{name.TrimStart('/')}";
    }

    private async Task<T> ExecuteWithLockAsync<T>(Func<Task<T>> action)
    {
        await _semaphore.WaitAsync();
        try
        {
            return await action();
        }
        finally
        {
            _semaphore.Release();
        }
    }

    private Task<bool> ExecuteWithLockAsync(Func<Task> action) =>
        ExecuteWithLockAsync(async () => { await action(); return true; });

    private Task<T> DeserializeFromFileAsync<T>(string filePath) =>
        File.ReadAllTextAsync(GetCollectionPath(filePath))
            .ContinueWith(t => JsonSerializer.Deserialize<T>(t.Result) ??
                throw new NullReferenceException("Deserialization result is null"));

    private async Task SerializeToFileAsync<T>(string filePath, T data)
    {
        var encodingName = _configuration["FlashSettings:SerializerOptions:Encoding"] ?? 
            throw new InvalidOperationException("FlashSettings:SerializerOptions:Encoding is not configured");
        string json = JsonSerializer.Serialize(data, GetSerializerOptions());
            await File.WriteAllTextAsync(GetCollectionPath(filePath), json,
                Encoding.GetEncoding(encodingName) ?? Encoding.Default);
    }

    private JsonSerializerOptions GetSerializerOptions()
    {
        var writeIndentedFlag = _configuration["FlashSettings:SerializerOptions:WriteIndented"] ??
            throw new InvalidOperationException("FlashSettings:SerializerOptions:WriteIndented is not configured");

        var unsafeEscapingFlag = _configuration["FlashSettings:SerializerOptions:UnsafeRelaxedJsonEscaping"] ??
            throw new InvalidOperationException("FlashSettings:SerializerOptions:UnsafeRelaxedJsonEscaping is not configured");

        return new()
        {
            WriteIndented = bool.Parse(writeIndentedFlag),
            Encoder = bool.Parse(unsafeEscapingFlag)
                ? JavaScriptEncoder.UnsafeRelaxedJsonEscaping
                : JavaScriptEncoder.Default
        };
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Defaults/Attributes.cs" << EOF
namespace ${agentname}.Agent.Data.Defaults;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct)]
public class CollectionNameAttribute(string name) : Attribute
{
    public string EntityName { get; init; } = name;
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Defaults/Extensions.cs" << EOF
using System.Reflection;

namespace ${agentname}.Agent.Data.Defaults;

internal static class CollectionNameAttributeExtensions
{
    public static string GetCollectionName(this Type entity)
    {
        try
        {
            return entity!.GetCustomAttribute<CollectionNameAttribute>()!.EntityName;
        }
        catch (Exception)
        {
            return $"{entity.Name}s";
        }
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Models/EntityBase.cs" << EOF
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ${agentname}.Agent.Data.Models;

public abstract class EntityBase<TId>
{
    [BsonId]
    [BsonRepresentation(BsonType.String)]
    public required TId Id { get; set; }

    [BsonRepresentation(BsonType.String)]
    public required DateTime CreatedAt { get; set; }

    public EntityBase()
    {
        CreatedAt = DateTime.UtcNow;
    }
}

public abstract class GuidEntity : EntityBase<Guid>
{
    [BsonRepresentation(BsonType.String)]
    public required DateTime UpdatedAt { get; set; }
    
    public GuidEntity() : base()
    {
        Id = Guid.NewGuid();
        UpdatedAt = CreatedAt;
    }

    public GuidEntity(Guid id) : base()
    {
        Id = id;
        UpdatedAt = CreatedAt;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Models/PagedList.cs" << EOF
using System.Collections;

namespace ${agentname}.Agent.Data.Models;

public class PagedList<TEntity>(
    IEnumerable<TEntity> items,
    int count,
    int pageNumber,
    int pageSize) : IReadOnlyList<TEntity>
{
    private readonly IList<TEntity> _subset = items as IList<TEntity> ?? [..items];

    public int PageNumber { get; } = pageNumber;
    public int TotalPages { get; } = (int)Math.Ceiling(count / (double)pageSize);

    public int Count { get; } = count;

    public bool IsFirstPage => PageNumber == 1;
    public bool IsLastPage => PageNumber == TotalPages;
    public bool HasNextPage => PageNumber < TotalPages;
    public bool HasPreviousPage => PageNumber > 1;


    public TEntity this[int index] => _subset[index];
    public IEnumerator<TEntity> GetEnumerator() => _subset.GetEnumerator();
    IEnumerator IEnumerable.GetEnumerator() => _subset.GetEnumerator();
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Models/TimespanFilter.cs" << EOF
namespace ${agentname}.Agent.Data.Models;

public record TimespanFilter
{
    public DateTime From { get; set; }
    public DateTime To {get; set; }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/Repository.cs" << EOF
namespace ${agentname}.Agent.Data.Repos;

public interface IRepository<TEntity> where TEntity : class
{
    Task<TEntity?> GetByIdAsync(Guid id);
    Task<TEntity> InsertAsync(TEntity entity);
    Task<TEntity> UpdateAsync(TEntity entity);
    ValueTask<bool> DeleteAsync(TEntity entity);
    ValueTask<bool> DeleteManyAsync(List<TEntity> entities);
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/RepositoryBuilder.cs" << EOF
using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Models;

namespace ${agentname}.Agent.Data.Repos;

public interface IRepositoryBuilder
{
    ICacheRepository<TEntity> CreateCacheRepository<TEntity>() where TEntity : GuidEntity;
    IFlashRepository<TEntity> CreateFlashRepository<TEntity>() where TEntity : GuidEntity;
    IMongoRepository<TEntity> CreateMongoRepository<TEntity>() where TEntity : GuidEntity;
}

internal class RepositoryBuilder(
    CacheContext cacheContext,
    FlashContext flashContext,
    MongoContext mongoContext)
    : IRepositoryBuilder
{
    public ICacheRepository<TEntity> CreateCacheRepository<TEntity>()
        where TEntity : GuidEntity => new CacheRepository<TEntity>(cacheContext);

    public IFlashRepository<TEntity> CreateFlashRepository<TEntity>()
        where TEntity : GuidEntity => new FlashRepository<TEntity>(flashContext);

    public IMongoRepository<TEntity> CreateMongoRepository<TEntity>()
        where TEntity : GuidEntity => new MongoRepository<TEntity>(mongoContext);
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/CacheRepository.cs" << EOF
using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Models;

namespace ${agentname}.Agent.Data.Repos;

public interface ICacheRepository<TEntity>: IRepository<TEntity> where TEntity : class { }

internal class CacheRepository<TEntity>(CacheContext context)
    : ICacheRepository<TEntity> where TEntity : GuidEntity
{
    public Task<TEntity?> GetByIdAsync(Guid id)
    {
        var (succeeded, entity) = context.GetEntity<TEntity>(id.ToString());

        return succeeded ? Task.FromResult(entity) : Task.FromResult(default(TEntity));
    }

    public Task<TEntity> InsertAsync(TEntity entity)
    {
        context.AddEntity(entity.Id.ToString(), entity);
        return Task.FromResult(entity);
    }

    public Task<TEntity> UpdateAsync(TEntity entity)
    {
        context.AddEntity(entity.Id.ToString(), entity);
        return Task.FromResult(entity);
    }

    public ValueTask<bool> DeleteAsync(TEntity entity)
    {
        context.RemoveEntity<TEntity>(entity.Id.ToString());
        return ValueTask.FromResult(true);
    }

    public ValueTask<bool> DeleteManyAsync(List<TEntity> entities)
    {
        throw new NotImplementedException();
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/FlashRepository.cs" << EOF
using System.Linq.Expressions;

using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Models;

namespace ${agentname}.Agent.Data.Repos;

public interface IFlashRepository<TEntity>: IRepository<TEntity> where TEntity : class
{
    Task<List<TEntity>> ToListAsync();
    Task<List<TEntity>> ToFilteredListAsync(Expression<Func<TEntity, bool>> filteringField);
    Task<TEntity?> GetFilteredEntity(Expression<Func<TEntity, bool>> filteringField);
}

internal class FlashRepository<TEntity>(FlashContext context)
    : IFlashRepository<TEntity> where TEntity : GuidEntity
{
    private const string CollectionNameFormat = "{0}sCollection.json";
    private const int FirstValidIndex = 0;
    
    private readonly FlashContext _context = context;

    public async Task<List<TEntity>> ToListAsync()
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        return [.. await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath)];
    }

    public async Task<List<TEntity>> ToFilteredListAsync(Expression<Func<TEntity, bool>> filteringField)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        return [.. collection.AsQueryable().Where(filteringField)];
    }

    public async Task<TEntity?> GetFilteredEntity(Expression<Func<TEntity, bool>> filteringField)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        return collection.AsQueryable().FirstOrDefault(filteringField);
    }

    public async Task<TEntity?> GetByIdAsync(Guid id)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        return collection.FirstOrDefault(e => e.Id == id);
    }

    public async Task<TEntity> InsertAsync(TEntity entity)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        collection.Add(entity);
        await _context.WriteToJsonCollectionAsync(collectionPath, collection);
        return entity;
    }

    public async Task<TEntity> UpdateAsync(TEntity entity)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        var index = collection.FindIndex(e => e.Id == entity.Id);
        if (index >= FirstValidIndex)
        {
            collection[index] = entity;
            await _context.WriteToJsonCollectionAsync(collectionPath, collection);
        }
        return entity;
    }

    public async ValueTask<bool> DeleteAsync(TEntity entity)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        var index = collection.FindIndex(e => e.Id == entity.Id);
        if (index >= FirstValidIndex)
        {
            collection.RemoveAt(index);
            await _context.WriteToJsonCollectionAsync(collectionPath, collection);
            return true;
        }
        return false;
    }

    public async ValueTask<bool> DeleteManyAsync(List<TEntity> entities)
    {
        var removed = false;
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        foreach (var entity in entities)
        {
            removed |= collection.Remove(entity);
        }
        if (removed)
        {
            await _context.WriteToJsonCollectionAsync(collectionPath, collection);
        }
        return removed;
    }

    private async ValueTask<string> GetCollectionPath(Type entityType)
    {
        var collectionPath = string.Format(CollectionNameFormat, entityType.Name);
        await _context.CheckCollectionAsync<List<Type>>(collectionPath);
        return collectionPath;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/MongoRepository.cs" << EOF
using System.Linq.Expressions;
using System.Runtime.CompilerServices;

using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Defaults;
using ${agentname}.Agent.Data.Models;

using MongoDB.Driver;
using MongoDB.Driver.Linq;

namespace ${agentname}.Agent.Data.Repos;

public interface IMongoRepository<TEntity> : IRepository<TEntity> where TEntity : class
{
    Task<TEntity> GetFilteredEntityAsync(Expression<Func<TEntity, bool>> predicate);
    Task<PagedList<TEntity>> GetPagedListAsync<TKey>(Expression<Func<TEntity, bool>> filter, Expression<Func<TEntity, TKey>> sorter, int page, int pageSize, bool asc);
    Task<List<TEntity>> GetFilteredSortedListAsync<TKey>(Expression<Func<TEntity, bool>> filter, Expression<Func<TEntity, TKey>> sorter, bool asc);
    Task<List<TEntity>> GetFilteredListAsync(Expression<Func<TEntity, bool>> filter);
    IAsyncEnumerable<TEntity> StreamCollectionItemsAsync(CancellationToken token, TimespanFilter? filter = default);
}

internal class MongoRepository<TEntity>(MongoContext context)
    : IMongoRepository<TEntity> where TEntity : GuidEntity
{
    private const int MaxRetries = 3;
    private const int BatchSize = 100;
    private const int SingleItemCount = 1;
    private const int EmptyCollectionCount = 0;
    private const int PageIndexOffset = 1;
    private const int RetryDelayBaseExponent = 2;
    private readonly MongoContext _context = context;
    protected IMongoCollection<TEntity> DbSet
        => _context.Database.GetCollection<TEntity>(
            typeof(TEntity).GetCollectionName());

    #region CRUD from default repository
    public async Task<TEntity?> GetByIdAsync(Guid id)
    {
        return await DbSet.AsQueryable().FirstOrDefaultAsync(e => e.Id == id);
    }
    public async Task<TEntity?> GetByIdAsync(string id)
    {
        return await DbSet.AsQueryable().FirstOrDefaultAsync(e => e.Id.ToString() == id);
    }
    public async Task<TEntity> InsertAsync(TEntity entity)
    {
        await DbSet.InsertOneAsync(entity);
        return entity;
    }
    public async Task<TEntity> UpdateAsync(TEntity entity)
    {
        await DbSet.ReplaceOneAsync(e => e.Id == entity.Id, entity);
        return entity;
    }
    public async ValueTask<bool> DeleteAsync(TEntity entity)
    {
        var result = await DbSet.DeleteOneAsync(e => e.Id == entity.Id);
        return result.DeletedCount == SingleItemCount;
    }
    public async ValueTask<bool> DeleteManyAsync(List<TEntity> entities)
    {
        var result = await DbSet.DeleteManyAsync(e => entities.Contains(e));
        return result.DeletedCount == entities.Count;
    }
    #endregion
    #region From IMongoRepository
    public async Task<TEntity> GetFilteredEntityAsync(Expression<Func<TEntity, bool>> predicate)
    {
        return await DbSet.AsQueryable().FirstOrDefaultAsync(predicate);
    }
    public async Task<List<TEntity>> GetFilteredListAsync(Expression<Func<TEntity, bool>> filter)
    {
        return await DbSet.AsQueryable().Where(filter).ToListAsync();
    }

    public async Task<PagedList<TEntity>> GetPagedListAsync<TKey>(
        Expression<Func<TEntity, bool>> filter,
        Expression<Func<TEntity, TKey>> sorter,
        int page, int pageSize, bool asc)
    {
        List<TEntity> results;
        var queryable = DbSet.AsQueryable();

        results = asc
            ? await queryable.Where(filter).OrderBy(sorter).Skip((page - PageIndexOffset) * pageSize).Take(pageSize).ToListAsync()
            : await queryable.Where(filter).OrderByDescending(sorter).Skip((page - PageIndexOffset) * pageSize).Take(pageSize).ToListAsync();
        return new PagedList<TEntity>(results, queryable.Where(filter).Count(), page, pageSize);
    }

    public async Task<List<TEntity>> GetFilteredSortedListAsync<TKey>(
        Expression<Func<TEntity, bool>> filter,
        Expression<Func<TEntity, TKey>> sorter,
        bool asc)
    {
        List<TEntity> results;
        var queryable = DbSet.AsQueryable();

        results = asc
            ? await queryable.Where(filter).OrderBy(sorter).ToListAsync()
            : await queryable.Where(filter).OrderByDescending(sorter).ToListAsync();
        return results;
    }
    #endregion
    #region Additional Data Streaming Methods
    public async IAsyncEnumerable<TEntity> StreamCollectionItemsAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken = default,
        TimespanFilter? timespan = default)
    {
        Guid? lastProcessedId = null;

        while (true)
        {
            var batchItems = await FetchBatchItemsAsync(lastProcessedId, timespan, cancellationToken);

            if (batchItems == null || batchItems.Count == EmptyCollectionCount)
            {
                yield break;
            }

            foreach (var collectionItem in batchItems)
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    yield break;
                }

                lastProcessedId = collectionItem.Id;
                await Task.Delay(_context.StreamingDelayMilliseconds, cancellationToken);

                yield return collectionItem;
            }
        }
    }

    private async Task<List<TEntity>?> FetchBatchItemsAsync(
        Guid? lastProcessedId,
        TimespanFilter? timespan,
        CancellationToken cancellationToken)
    {
        var options = CreateFindOptions();
        var filter = timespan is null
            ? CreateFilter(lastProcessedId)
            : CreateFilter(lastProcessedId, timespan);

        for (int attempt = 0; attempt < MaxRetries; attempt++)
        {
            try
            {
                using var cursor = await DbSet.FindAsync(filter, options, cancellationToken);
                return await cursor.ToListAsync(cancellationToken);
            }
            catch (MongoException)
            {
                if (attempt == MaxRetries - SingleItemCount)
                {
                    throw;
                }

                await Task.Delay(TimeSpan.FromSeconds(Math.Pow(RetryDelayBaseExponent, attempt)), cancellationToken);
            }
        }

        return null;
    }

    private static FilterDefinition<TEntity> CreateFilter(Guid? lastProcessedId)
    {
        var baseFilter = Builders<TEntity>.Filter.Empty;
        return lastProcessedId.HasValue
            ? Builders<TEntity>.Filter.Gt(x => x.Id, lastProcessedId.Value)
            : baseFilter;
    }

    private static FilterDefinition<TEntity> CreateFilter(Guid? lastProcessedId, TimespanFilter timespan)
    {
        var baseFilter = Builders<TEntity>.Filter.And(
            Builders<TEntity>.Filter.Gte(x => x.CreatedAt, timespan.From),
            Builders<TEntity>.Filter.Lte(x => x.CreatedAt, timespan.To)
        );

        if (lastProcessedId.HasValue)
        {
            baseFilter = Builders<TEntity>.Filter.And(
                baseFilter,
                Builders<TEntity>.Filter.Gt(x => x.Id, lastProcessedId.Value)
            );
        }

        return baseFilter;
    }

    private static FindOptions<TEntity> CreateFindOptions()
    {
        return new FindOptions<TEntity>
        {
            BatchSize = BatchSize,
            Sort = Builders<TEntity>.Sort.Ascending(x => x.Id)
        };
    }
    #endregion
}
EOF

# Create basic CQRS structure
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Commands"
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Queries"
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Models"
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Handlers"

# Create example Command and Query files
cat > "${basepath}/${agentname}.Agent.Cqrs/Commands/ExampleCommand.cs" << EOF
using MediatR;

namespace ${agentname}.Agent.Cqrs.Commands
{
    public class ExampleCommand : IRequest<bool>
    {
        public string Data { get; set; } = string.Empty;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Cqrs/Queries/ExampleQuery.cs" << EOF
using MediatR;

namespace ${agentname}.Agent.Cqrs.Queries
{
    public class ExampleQuery : IRequest<string>
    {
        public string Id { get; set; } = string.Empty;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Cqrs/Handlers/ExampleCommandHandler.cs" << EOF
using MediatR;
using ${agentname}.Agent.Cqrs.Commands;

namespace ${agentname}.Agent.Cqrs.Handlers
{
    public class ExampleCommandHandler : IRequestHandler<ExampleCommand, bool>
    {
        public Task<bool> Handle(ExampleCommand request, CancellationToken cancellationToken)
        {
            // Example implementation
            return Task.FromResult(true);
        }
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Cqrs/Handlers/ExampleQueryHandler.cs" << EOF
using MediatR;
using ${agentname}.Agent.Cqrs.Queries;

namespace ${agentname}.Agent.Cqrs.Handlers
{
    public class ExampleQueryHandler : IRequestHandler<ExampleQuery, string>
    {
        public Task<string> Handle(ExampleQuery request, CancellationToken cancellationToken)
        {
            // Example implementation
            return Task.FromResult(\$"Response for ID: {request.Id}");
        }
    }
}
EOF

# Create sample controllers
mkdir -p "${basepath}/${agentname}.Api.Endpoints/Controllers"
cat > "${basepath}/${agentname}.Api.Endpoints/Controllers/ExampleController.cs" << EOF
using MediatR;
using Microsoft.AspNetCore.Mvc;
using ${agentname}.Agent.Cqrs.Commands;
using ${agentname}.Agent.Cqrs.Queries;

namespace ${agentname}.Api.Endpoints.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ExampleController : ControllerBase
    {
        private readonly IMediator _mediator;

        public ExampleController(IMediator mediator)
        {
            _mediator = mediator;
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Get(string id)
        {
            var query = new ExampleQuery { Id = id };
            var result = await _mediator.Send(query);
            return Ok(result);
        }

        [HttpPost]
        public async Task<IActionResult> Post([FromBody] ExampleCommand command)
        {
            var result = await _mediator.Send(command);
            return Ok(result);
        }
    }
}
EOF

mkdir -p "${basepath}/${agentname}.Mcp.Endpoints/Controllers"
cat > "${basepath}/${agentname}.Mcp.Endpoints/Controllers/ExampleController.cs" << EOF
using MediatR;
using Microsoft.AspNetCore.Mvc;
using ${agentname}.Agent.Cqrs.Commands;
using ${agentname}.Agent.Cqrs.Queries;

namespace ${agentname}.Mcp.Endpoints.Controllers
{
    [ApiController]
    [Route("mcp/[controller]")]
    public class ChatController : ControllerBase
    {
        private readonly IMediator _mediator;

        public ChatController(IMediator mediator)
        {
            _mediator = mediator;
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Get(string id)
        {
            var query = new ExampleQuery { Id = id };
            var result = await _mediator.Send(query);
            return Ok(result);
        }

        [HttpPost]
        public async Task<IActionResult> Post([FromBody] ExampleCommand command)
        {
            var result = await _mediator.Send(command);
            return Ok(result);
        }
    }
}
EOF

# Update Program.cs files to include MediatR and Swagger
cat > "${basepath}/${agentname}.Api.Endpoints/Program.cs" << EOF
using System.Reflection;
using ${agentname}.Agent.Cqrs.Commands;
using MediatR;

var builder = WebApplication.CreateBuilder(args);

// Add defaults services to the container.
builder.AddServiceDefaults();

// Add services to the container.
builder.Services.AddControllers();

// Add MediatR
builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(ExampleCommand).Assembly));

// Add Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseHttpsRedirection();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthorization();
app.MapControllers();

app.Run();
EOF

cat > "${basepath}/${agentname}.Mcp.Endpoints/Program.cs" << EOF
using System.Reflection;
using ${agentname}.Agent.Cqrs.Commands;
using MediatR;

var builder = WebApplication.CreateBuilder(args);

// Add defaults services to the container.
builder.AddServiceDefaults();

// Add services to the container.
builder.Services.AddControllers();

// Add MediatR
builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(ExampleCommand).Assembly));

// Add Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseHttpsRedirection();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthorization();
app.MapControllers();

app.Run();
EOF

cat > "${basepath}/${agentname}.Web.Endpoints/Program.cs" << EOF
using Microsoft.Extensions.FileProviders;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();

var app = builder.Build();

// Add static files middleware for Assets/Files directory
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(
        Path.Combine(Directory.GetCurrentDirectory(), "Assets", "Files")),
    RequestPath = "/Files"
});

app.MapGet("/", async (HttpContext httpContext) =>
{
    var contentPath = Path.Combine("Assets", $"index.html");
    if (!File.Exists(contentPath))
    {
        return Results.NotFound($"File not found: {contentPath}");
    }

    var content = await File.ReadAllTextAsync(contentPath);
    return Results.Content(content, "text/html");
});

app.Run();
EOF

# Create Assets directory and index.html for Web.Endpoints
mkdir -p "${basepath}/${agentname}.Web.Endpoints/Assets/Files"

# Create index.html
cat > "${basepath}/${agentname}.Web.Endpoints/Assets/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Web Agents Template | BIZMASTER AGENCY</title>
    <!-- Material Design Icons -->
    <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
    <!-- Material Design Web Components -->
    <link href="https://fonts.googleapis.com/css?family=Roboto:300,400,500" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Roboto', sans-serif;
        }
        
        body {
            background-color: #f5f5f5;
            color: #333;
            line-height: 1.6;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 2rem;
        }
        
        .container {
            max-width: 800px;
            width: 100%;
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
            overflow: hidden;
            margin: 0 auto;
            transition: all 0.3s ease;
        }
        
        .header {
            background-color: #2196F3;
            color: white;
            padding: 2rem;
            text-align: center;
        }
        
        .header h1 {
            font-weight: 400;
            margin-bottom: 0.5rem;
            font-size: 2rem;
        }
        
        .header p {
            font-weight: 300;
            opacity: 0.9;
        }
        
        .content {
            padding: 2rem;
        }
        
        .feature {
            display: flex;
            align-items: center;
            margin-bottom: 1.5rem;
        }
        
        .feature-icon {
            background-color: #2196F3;
            color: white;
            width: 50px;
            height: 50px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-right: 1rem;
            flex-shrink: 0;
            font-size: 1.8rem; /* Increased font size for emojis */
        }
        
        .feature-text h3 {
            font-weight: 500;
            margin-bottom: 0.3rem;
            color: #1976D2;
        }
        
        .footer {
            background-color: #f9f9f9;
            padding: 1.5rem 2rem;
            text-align: center;
            border-top: 1px solid #eee;
        }
        
        .footer a {
            color: #2196F3;
            text-decoration: none;
            transition: color 0.3s;
        }
        
        .footer a:hover {
            color: #0D47A1;
            text-decoration: underline;
        }
        
        .cta-button {
            background-color: #2196F3;
            color: white;
            border: none;
            padding: 0.8rem 1.5rem;
            font-size: 1rem;
            border-radius: 4px;
            cursor: pointer;
            margin-top: 1.5rem;
            box-shadow: 0 2px 5px rgba(0, 0, 0, 0.1);
            transition: all 0.3s ease;
            display: inline-block;
            text-decoration: none;
        }
        
        .cta-button:hover {
            background-color: #1976D2;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2);
            transform: translateY(-2px);
        }
        
        /* Responsive design */
        @media (max-width: 768px) {
            .header {
                padding: 1.5rem;
            }
            
            .header h1 {
                font-size: 1.8rem;
            }
            
            .content {
                padding: 1.5rem;
            }
            
            .feature {
                flex-direction: column;
                text-align: center;
            }
            
            .feature-icon {
                margin-right: 0;
                margin-bottom: 1rem;
            }
        }
        
        @media (max-width: 480px) {
            body {
                padding: 1rem;
            }
            
            .header {
                padding: 1.2rem;
            }
            
            .header h1 {
                font-size: 1.5rem;
            }
            
            .content {
                padding: 1.2rem;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>AI Web Agents Starter Kit</h1>
            <p>A comprehensive framework for developing intelligent web agents</p>
        </div>
        
        <div class="content">
            <div class="feature">
                <div class="feature-icon">
                    <span>👨‍💻</span>
                </div>
                <div class="feature-text">
                    <h3>Developer-Friendly</h3>
                    <p>Build powerful AI web agents with our streamlined template designed for maximum productivity and efficiency.</p>
                </div>
            </div>
            
            <div class="feature">
                <div class="feature-icon">
                    <span>🤖</span>
                </div>
                <div class="feature-text">
                    <h3>AI-Powered</h3>
                    <p>Leverage cutting-edge artificial intelligence capabilities to create responsive and intelligent web agents.</p>
                </div>
            </div>
            
            <div class="feature">
                <div class="feature-icon">
                    <span>🔌</span>
                </div>
                <div class="feature-text">
                    <h3>Easy Integration</h3>
                    <p>Seamlessly integrate with existing systems using our well-designed API endpoints and Model Context Protocol.</p>
                </div>
            </div>
            
            <div style="text-align: center; margin-top: 2rem;">
                <a href="https://www.bizmaster.agency" class="cta-button">Learn More</a>
            </div>
        </div>
        
        <div class="footer">
            <p>Developed by <a href="https://www.bizmaster.agency" target="_blank">BIZMASTER AGENCY</a> &copy; 2025</p>
        </div>
    </div>
</body>
</html>
EOF

# Create sample DID file in Assets/Files
cat > "${basepath}/${agentname}.Web.Endpoints/Assets/Files/did.txt" << EOF
some did structure placed here
EOF

# Update Agent's Program.cs to properly register services
cat > "${basepath}/${agentname}.Agent/AppHost.cs" << EOF
var builder = DistributedApplication.CreateBuilder(args);

var apiService = builder.AddProject<Projects.${agentname}_Api_Endpoints>("api-endpoints");
var mcpService = builder.AddProject<Projects.${agentname}_Mcp_Endpoints>("mcp-endpoints");
var webService = builder.AddProject<Projects.${agentname}_Web_Endpoints>("web-endpoints");

builder.Build().Run();
EOF

# Create a README.md with documentation about the project structure
cat > "${basepath}/README.md" << EOF
# ${agentname} Project

This project was generated using the agent_starter_kit.sh script.

## Project Structure

- **${agentname}.Agent**: Aspire app host that coordinates all services
- **${agentname}.Agent.Cqrs**: Class library containing CQRS commands, queries, and handlers
- **${agentname}.Agent.Data**: Data access library (Mongo, in-memory cache, flash storage) with repositories and models
- **${agentname}.Y.Core**: Aspire service defaults for configuration
- **${agentname}.Api.Endpoints**: Web API for external API endpoints
- **${agentname}.Mcp.Endpoints**: Web API for Model Context Protocol endpoints
- **${agentname}.Web.Endpoints**: Web application for UI

## Getting Started

1. Build the solution: \`dotnet build\`
2. Run the solution: \`dotnet run --project ${agentname}.Agent/${agentname}.Agent.csproj\`

## Dependencies

- .NET 9.0+
- .NET Aspire
- MediatR for CQRS
- FluentValidation
- Swashbuckle for OpenAPI/Swagger

EOF

# Create AGENTS.md documentation file
cat > "${basepath}/AGENTS.md" << EOF
# AGENTS.md

## Purpose

This document describes the agents used in this project, their roles, and their configurations. The AGENTS.md file serves as a dedicated reference for AI coding agents to better understand the project structure and automate development tasks.

## Agents Overview

The project uses several specialized agents that handle different aspects of the codebase. Each agent has a specific role and configuration detailed in separate markdown files within the \`agent_actions\` directory.

### Orchestration Agent

- **Agent Name:** Agent Action Orchestrator (Chain of Responsibility Pattern)
- **Role:** Implements the Chain of Responsibility pattern to coordinate workflow execution through a series of handlers that process requests sequentially until one can handle it
- **Pattern Type:** Chain of Responsibility (also known as Chain of Command or State Machine pattern)
- **Key Features:** Type-safe request/response handling, configurable timeout and validation, comprehensive logging, dependency injection integration, thread-safe operations
- **Configuration:** [See detailed documentation](agent_actions/AGENT_ACTION_CHOR.md)

### Controller Agent

- **Agent Name:** Agent Action Controller 
- **Role:** Manages request handling and routes actions to appropriate processors
- **Configuration:** [See detailed documentation](agent_actions/AGENT_ACTION_CONTROLLER.md)

### CQRS Agent

- **Agent Name:** Agent Action CQRS
- **Role:** Implements Command Query Responsibility Segregation pattern for data operations
- **Configuration:** [See detailed documentation](agent_actions/AGENT_ACTION_CQRS.md)

### Data Agent

- **Agent Name:** Agent Action Data
- **Role:** Handles data processing, storage, and retrieval operations
- **Configuration:** [See detailed documentation](agent_actions/AGENT_ACTION_DATA.md)

## Agent Communication Flow

Agents communicate through a well-defined pipeline:
1. The Orchestrator coordinates the overall process
2. The Controller receives and routes requests
3. The CQRS agent separates read and write operations
4. The Data agent performs the actual data manipulations

## Development Guidelines

When modifying agent behavior:
1. Update the relevant agent_actions/*.md file with changes
2. Ensure backward compatibility or document breaking changes
3. Test agent interactions to verify functionality
4. Update this overview document for major architectural changes

## Code Style Guidelines

The project follows strict code style conventions to ensure consistency and maintainability across all components:

### General Coding Principles

- Use **primary constructors** for cleaner and more concise class definitions
- Follow **camel case naming** conventions for variables and parameters
- Use **PascalCase** for class names, method names, and public members
- Use **[..]** syntax for array initializations instead of \`new T[]\`
- Implement **partial classes** for complex regex operations and generated code
- Use **ValueTask** for non-reference variables and value structures to improve performance

### Type Usage Guidelines

- Use **records** for DTOs (Data Transfer Objects) and immutable value objects
- Use **classes** for models and implementations with behavior
- Create **custom errors** for specific scopes (libraries, modules, etc.) to improve error handling and debugging

### Documentation Standards

- Include **detailed XML comments** for all classes, methods, functions, interfaces, and public properties
- Document parameters, return values, exceptions, and examples where applicable
- Follow the standard XML documentation format compatible with documentation generators

### Testing Framework and Conventions

- Use **xUnit** as the primary unit testing framework for all test automation
- Follow the naming convention **\\*.Tests** for test projects (e.g., \`Agent.Core\` → \`Agent.Core.Tests\`)
- Organize test classes to mirror the structure of the code being tested
- Write test methods using the pattern \`[MethodName]_[Scenario]_[ExpectedResult]\`
- Include both positive and negative test cases for comprehensive coverage

For more detailed coding standards, refer to the project style guide: [Code Style Guidelines](agent_actions/AGENT_ACTION_CODESTYLE.md)

---

> **Note:** As this project evolves, keep agent documentation current to assist both human contributors and AI agents.
EOF

# Create agent_actions directory and documentation files
mkdir -p "${basepath}/agent_actions"

# Create AGENT_ACTION_CHOR.md (Chain of Responsibility Pattern)
cat > "${basepath}/agent_actions/AGENT_ACTION_CHOR.md" << 'EOF'
# *.Agent.Inventory

A .NET 9.0 library providing flexible programming patterns for inventory operations in the Cheshire Agent system. This library serves as an inventory box of proven design patterns that can be reused across the solution.

## Overview

This library contains production-ready implementations of common design patterns, organized following SOLID principles for maximum reusability and maintainability.

## Available Patterns

### 1. Chain of Responsibility Pattern ⭐ **NEW & IMPROVED**

A robust, production-ready implementation of the Chain of Responsibility pattern (also known as Chain of Command or State Machine pattern).

**Location**: `ChainOfResponsibility/`

**Key Features**:
- Type-safe request/response handling
- Configurable timeout and validation
- Comprehensive logging and error handling
- Dependency injection integration
- Thread-safe operations

**Quick Start**:
```csharp
// Register services
services.InjectInventoryServices();

// Define request/response
public record MyRequest : BaseRequest { public string Data { get; init; } = ""; }
public record MyResponse : BaseResponse { public string Result { get; init; } = ""; }

// Create handler
public class MyHandler : BaseRequestHandler<MyRequest, MyResponse>
{
    public MyHandler(ILogger<MyHandler> logger) : base(logger) { }
    
    public override bool CanHandle(MyRequest request) => !string.IsNullOrEmpty(request.Data);
    
    protected override async Task<MyResponse> ProcessRequestAsync(MyRequest request, CancellationToken cancellationToken)
    {
        return new MyResponse { RequestId = request.RequestId, Result = $"Processed: {request.Data}" };
    }
}

// Build and execute chain
var chain = chainBuilder.AddHandler<MyHandler>().Build();
var response = await orchestrator.ExecuteAsync(chain, request);
```

📖 **[Complete Documentation](ChainOfResponsibility/CHOR_README.md)**

### 2. Legacy Pipeline Pattern (Backward Compatibility)

The original pipeline implementation is maintained for backward compatibility.

**Location**: Root directory (`Pipeline.cs`, `PipelineBuilder.cs`, `PipelineItem.cs`)

**Migration Note**: Consider migrating to the new Chain of Responsibility pattern for new implementations.

## Project Structure

```
*.Agent.Inventory/
├── ChainOfResponsibility/              # 🆕 New Chain of Responsibility pattern
│   ├── Abstractions/                   # Core interfaces and base classes
│   │   ├── IRequestHandler.cs
│   │   ├── IChainBuilder.cs
│   │   └── BaseRequestHandler.cs
│   ├── Models/                         # Request/Response models and configuration
│   │   ├── BaseRequest.cs
│   │   ├── BaseResponse.cs
│   │   └── ChainConfiguration.cs
│   ├── Implementations/                # Concrete implementations
│   │   ├── ChainBuilder.cs
│   │   └── ChainOrchestrator.cs
│   ├── Extensions/                     # Service collection extensions
│   │   └── ServiceCollectionExtensions.cs
│   ├── Exceptions/                     # Custom exceptions
│       └── ChainExceptions.cs
├── *.Agent.Inventory.csproj
├── CHOR_README.md
├── Injector.cs                         # 🔄 Updated with new services
```

## Integration with Cheshire Ecosystem

This library is designed to integrate seamlessly with other Cheshire components:

- ***.Agent.Cqrs**: Use Chain of Responsibility for command/query handling
- ***.Services.Scrapper**: Chain handlers for different content types
- ***.Api.Endpoints**: Request processing pipelines
- ***.Web.Endpoints**: Web request processing chains

## Getting Started

### Installation

Add reference to your project:
```xml
<ProjectReference Include="*.Agent.Inventory\*.Agent.Inventory.csproj" />
```

### Basic Setup

```csharp
// In Program.cs or Startup.cs
services.InjectInventoryServices();

// Register your handlers
services.AddRequestHandler<YourHandler, YourRequest, YourResponse>();
```

### Advanced Configuration

```csharp
services.AddChainOfResponsibility(config =>
{
    config.EnableDetailedLogging = true;
    config.Timeout = TimeSpan.FromMinutes(10);
    config.MaxHandlers = 50;
});
```

## Design Principles

This library follows SOLID principles:

- **Single Responsibility**: Each handler focuses on one specific concern
- **Open/Closed**: Easy to extend with new handlers without modifying existing code
- **Liskov Substitution**: All handlers implement the same interface contract
- **Interface Segregation**: Focused interfaces for specific purposes
- **Dependency Inversion**: Depends on abstractions, not concrete implementations

## Best Practices

1. **DRY (Don't Repeat Yourself)**: Reuse common patterns across the solution
2. **KISS (Keep It Simple, Stupid)**: Simple, focused implementations
3. **SOLID Principles**: Well-structured, maintainable code
4. **Comprehensive Testing**: Each pattern includes testable components
5. **Documentation**: Detailed usage examples and API documentation

## Dependencies

- Microsoft.Extensions.DependencyInjection (9.0.1)
- Microsoft.Extensions.Logging (9.0.1)
- .NET 9.0

## Contributing

When adding new patterns to this inventory:

1. Create a dedicated folder following the same structure
2. Include comprehensive documentation with examples
3. Follow SOLID principles and maintain consistency
4. Add appropriate unit tests
5. Update this *README with the new pattern

## Future Patterns

Planned additions to the pattern inventory:

- **Strategy Pattern**: For interchangeable algorithms
- **Observer Pattern**: For event-driven architectures  
- **Factory Pattern**: For object creation strategies
- **Decorator Pattern**: For behavior extension
- **State Machine Pattern**: For complex state management
EOF

# Create AGENT_ACTION_CODESTYLE.md (Code Style Guidelines)
cat > "${basepath}/agent_actions/AGENT_ACTION_CODESTYLE.md" << 'EOF'
# Code Style Guidelines

This document provides detailed coding standards and style guidelines for the project. Following these guidelines ensures consistency across the codebase and makes it easier for both human developers and AI agents to understand and maintain the code.

## C# Language Features

### Primary Constructors

Use primary constructors for cleaner class definitions:

```csharp
// Preferred
public class User(string name, string email)
{
    public string Name { get; } = name;
    public string Email { get; } = email;
}

// Instead of
public class User
{
    public User(string name, string email)
    {
        Name = name;
        Email = email;
    }

    public string Name { get; }
    public string Email { get; }
}
```

### Records vs Classes

Use records for immutable data structures:

```csharp
// Use records for DTOs and value objects
public record UserDto(string Name, string Email, DateTime CreatedAt);

// Use classes for models with behavior
public class UserModel
{
    public string Name { get; set; }
    public string Email { get; set; }
    
    public bool IsValidEmail() => Email.Contains("@") && Email.Contains(".");
}
```

### Array Initialization

Use collection initializer syntax:

```csharp
// Preferred
var numbers = [1, 2, 3, 4, 5];

// Instead of
var numbers = new int[] { 1, 2, 3, 4, 5 };
```

### Partial Classes for Regex

Use partial classes to organize regex patterns:

```csharp
// EmailValidator.cs
public partial class EmailValidator
{
    public bool IsValid(string email) => EmailRegex().IsMatch(email);
}

// EmailValidator.Regex.cs
public partial class EmailValidator
{
    [GeneratedRegex(@"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$")]
    private static partial Regex EmailRegex();
}
```

### ValueTask Usage

Use ValueTask for performance-critical operations:

```csharp
// Use for non-reference variables and value structures
public ValueTask<int> GetCountAsync() => new ValueTask<int>(_count);

// Use Task for reference types or async operations
public Task<User> GetUserAsync() => _repository.GetUserAsync(userId);
```

## Naming Conventions

### Variables and Parameters

- Use camelCase for local variables and method parameters
- Use meaningful, descriptive names that indicate purpose
- Avoid single-letter variable names except for loop counters

```csharp
// Good
void ProcessUser(string userName, int userAge)
{
    var formattedName = FormatName(userName);
    for (int i = 0; i < userCount; i++)
    {
        // ...
    }
}

// Avoid
void Process(string u, int a)
{
    var n = Format(u);
    for (int x = 0; x < count; x++)
    {
        // ...
    }
}
```

### Class and Method Names

- Use PascalCase for class names and method names
- Choose clear, descriptive names that reflect purpose
- Prefix interfaces with 'I' (e.g., IRepository)

```csharp
// Good
public interface IUserRepository
{
    Task<User> GetUserByIdAsync(Guid userId);
}

// Good
public class UserRepository : IUserRepository
{
    public Task<User> GetUserByIdAsync(Guid userId) => // implementation
}
```

## Custom Error Handling

Create custom exceptions for specific scopes:

```csharp
// Library-specific exceptions
public class AgentDataException : Exception
{
    public AgentDataException(string message) : base(message) { }
    public AgentDataException(string message, Exception inner) : base(message, inner) { }
}

// Module-specific exceptions
public class CqrsValidationException : Exception
{
    public IDictionary<string, string[]> ValidationErrors { get; }
    
    public CqrsValidationException(IDictionary<string, string[]> validationErrors)
        : base("One or more validation errors occurred.")
    {
        ValidationErrors = validationErrors;
    }
}
```

## Documentation Standards

All public APIs should include XML documentation:

```csharp
/// <summary>
/// Processes a user request and returns a response.
/// </summary>
/// <param name="request">The user request to process.</param>
/// <returns>A response containing the processed data.</returns>
/// <exception cref="ArgumentNullException">Thrown when <paramref name="request"/> is null.</exception>
/// <example>
/// <code>
/// var request = new UserRequest("John");
/// var response = processor.ProcessRequest(request);
/// </code>
/// </example>
public UserResponse ProcessRequest(UserRequest request)
{
    if (request == null) throw new ArgumentNullException(nameof(request));
    // Implementation
}
```

## Unit Testing Standards

### Project Structure

- Create a test project for each production project
- Follow the naming pattern `*.Tests` (e.g., `Agent.Core.Tests`)
- Mirror the folder structure of the production code

### Test Class Organization

```csharp
// [ClassUnderTest]Tests.cs
public class UserServiceTests
{
    // Arrange fields and test fixtures
    private readonly IUserRepository _mockRepository;
    private readonly UserService _sut; // System Under Test
    
    public UserServiceTests()
    {
        _mockRepository = Substitute.For<IUserRepository>();
        _sut = new UserService(_mockRepository);
    }
    
    // Group tests by method
    
    // [MethodName]_[Scenario]_[ExpectedResult]
    [Fact]
    public async Task GetUserById_WithValidId_ReturnsUser()
    {
        // Arrange
        var userId = Guid.NewGuid();
        var expectedUser = new User(userId, "Test User");
        _mockRepository.GetUserByIdAsync(userId).Returns(expectedUser);
        
        // Act
        var result = await _sut.GetUserByIdAsync(userId);
        
        // Assert
        Assert.Equal(expectedUser, result);
    }
    
    [Fact]
    public async Task GetUserById_WithInvalidId_ThrowsNotFoundException()
    {
        // Arrange
        var userId = Guid.NewGuid();
        _mockRepository.GetUserByIdAsync(userId).Returns((User)null);
        
        // Act & Assert
        await Assert.ThrowsAsync<UserNotFoundException>(
            () => _sut.GetUserByIdAsync(userId));
    }
}
```

## Common Anti-patterns to Avoid

1. **God Classes/Methods** - Classes or methods that try to do too much
2. **Excessive Nesting** - Avoid deeply nested if-statements or loops
3. **Magic Numbers/Strings** - Use named constants instead
4. **Duplicate Code** - Refactor common functionality into shared methods
5. **Improper Exception Handling** - Avoid empty catch blocks
6. **Non-descriptive Names** - Avoid unclear abbreviations or generic names
7. **Public Fields** - Use properties with appropriate access modifiers
8. **Commented Out Code** - Remove or document why it's needed
EOF

# Create AGENT_ACTION_CONTROLLER.md (Controller Method Implementation)
cat > "${basepath}/agent_actions/AGENT_ACTION_CONTROLLER.md" << 'EOF'
# AGENT_ACTION Template for Controller Method Implementation

## Universal Template for CQRS-based Controller Methods

Use this template to generate controller methods based on CQRS commands and queries with proper error handling, logging, and status codes.

### Template Variables:
- `{mthd-name}` - Method name based on CQRS query/command naming strategy
- `{mthd-rout}` - Controller method route
- `{Command/Query}` - CQRS Command or Query class name
- `{ReturnType}` - Expected return type from the command/query
- `{HttpMethod}` - HTTP method (GET, POST, PUT, DELETE)

## Swagger UI Response Object Configuration

### ProducesResponseType with Generic Return Types

For proper Swagger UI documentation, always specify the exact return type using `ProducesResponseType<T>` where `T` is the CQRS command/query result type.

#### Template for Response Type Attributes:
```csharp
// For successful responses with data (200/201)
[ProducesResponseType<{ReturnType}>(StatusCodes.Status200OK)]
[ProducesResponseType<{ReturnType}>(StatusCodes.Status201Created)] // For POST operations

// For error responses with standard error models
[ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status500InternalServerError)]
```

## GET Method Template (Query)

```csharp
/// <summary>
/// {mthd-name} - Executes {Query} to retrieve data
/// </summary>
/// <param name="parameters">Route/query parameters for the request</param>
/// <returns>
/// Returns:
/// [200] - Success with {ReturnType} data
/// [400] - Bad Request - Invalid input parameters
/// [404] - Not Found - Resource does not exist  
/// [500] - Internal Server Error - Unexpected error occurred
/// </returns>
[HttpGet("{mthd-rout}")]
[ProducesResponseType<{ReturnType}>(StatusCodes.Status200OK)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status500InternalServerError)]
public async Task<IActionResult> {mthd-name}(
    [FromRoute] /* parameters */)
{
    try
    {
        _logger.LogInformation("Executing {mthd-name} with parameters: {@Parameters}", /* parameters */);
        
        var query = new {Query}
        {
            // Map parameters to query properties
        };
        
        var result = await _mediator.Send(query);
        
        if (result == null)
        {
            _logger.LogWarning("{mthd-name} returned null result for parameters: {@Parameters}", /* parameters */);
            return NotFound("Resource not found");
        }
        
        _logger.LogInformation("{mthd-name} completed successfully");
        return Ok(result);
    }
    catch (ArgumentException ex)
    {
        _logger.LogWarning(ex, "{mthd-name} failed due to invalid arguments: {@Parameters}", /* parameters */);
        return BadRequest(ex.Message);
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "{mthd-name} failed with unexpected error for parameters: {@Parameters}", /* parameters */);
        return StatusCode(StatusCodes.Status500InternalServerError, "An unexpected error occurred");
    }
}
```

## POST Method Template (Command)

```csharp
/// <summary>
/// {mthd-name} - Executes {Command} to create/process data
/// </summary>
/// <param name="command">The command object containing the data to process</param>
/// <returns>
/// Returns:
/// [200] - Success with {ReturnType} result
/// [201] - Created successfully with {ReturnType} data
/// [400] - Bad Request - Invalid input data
/// [409] - Conflict - Business logic violation
/// [500] - Internal Server Error - Unexpected error occurred
/// </returns>
[HttpPost("{mthd-rout}")]
[ProducesResponseType<{ReturnType}>(StatusCodes.Status200OK)]
[ProducesResponseType<{ReturnType}>(StatusCodes.Status201Created)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status500InternalServerError)]
public async Task<IActionResult> {mthd-name}(
    [FromBody] {Command} command)
{
    try
    {
        _logger.LogInformation("Executing {mthd-name} with command: {@Command}", command);
        
        var result = await _mediator.Send(command);
        
        _logger.LogInformation("{mthd-name} completed successfully with result: {@Result}", result);
        
        // For creation operations, return 201 Created
        // For update operations, return 200 OK
        return Ok(result); // or CreatedAtAction(...) for creation
    }
    catch (ArgumentException ex)
    {
        _logger.LogWarning(ex, "{mthd-name} failed due to invalid arguments: {@Command}", command);
        return BadRequest(ex.Message);
    }
    catch (InvalidOperationException ex)
    {
        _logger.LogWarning(ex, "{mthd-name} failed due to business logic conflict: {@Command}", command);
        return Conflict(ex.Message);
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "{mthd-name} failed with unexpected error for command: {@Command}", command);
        return StatusCode(StatusCodes.Status500InternalServerError, "An unexpected error occurred");
    }
}
```

## Controller Class Template Requirements

### Required Using Statements:
```csharp
using MediatR;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using FluentValidation;
using *.Agent.Cqrs.Commands;
using *.Agent.Cqrs.Queries;
using *.Agent.Cqrs.Models;
```

### Controller Class Declaration with Primary Constructor:
```csharp
[ApiController]
[Route("api/[controller]")]
public class {ControllerName}Controller(
    IMediator mediator,
    ILogger<{ControllerName}Controller> logger) : ControllerBase
{
    private readonly IMediator _mediator = mediator;
    private readonly ILogger<{ControllerName}Controller> _logger = logger;
}
```

## Naming Strategy Examples:

### For Query: `GetUserByIdQuery`
- **{mthd-name}**: `GetUserById`
- **{mthd-rout}**: `"{id}"`
- **Method**: `[HttpGet("{id}")]`

### For Command: `CreateUserCommand`
- **{mthd-name}**: `CreateUser`
- **{mthd-rout}**: `""` (empty for POST to base route)
- **Method**: `[HttpPost]`

### For Command: `UpdateUserCommand`
- **{mthd-name}**: `UpdateUser`
- **{mthd-rout}**: `"{id}"`
- **Method**: `[HttpPut("{id}")]`

### For Command: `DeleteUserCommand`
- **{mthd-name}**: `DeleteUser`
- **{mthd-rout}**: `"{id}"`
- **Method**: `[HttpDelete("{id}")]`

## Common Exception Handling Patterns:

1. **ArgumentException** → 400 Bad Request
2. **KeyNotFoundException** → 404 Not Found
3. **InvalidOperationException** → 409 Conflict
4. **UnauthorizedAccessException** → 401 Unauthorized
5. **Exception** (catch-all) → 500 Internal Server Error

## Logging Best Practices:

1. Log method entry with parameters
2. Log warnings for business logic issues (400, 404, 409 responses)
3. Log errors for unexpected exceptions (500 responses)
4. Log success with relevant result information
5. Use structured logging with `{@Object}` for complex objects
EOF

# Create AGENT_ACTION_CQRS.md (CQRS Component Generation)
cat > "${basepath}/agent_actions/AGENT_ACTION_CQRS.md" << 'EOF'
# CQRS Component Generation Prompt

Generate CQRS (Command Query Responsibility Segregation) components for the *.Agent.Cqrs project based on the following specifications.

## Parameters
- **{cqrs-action}**: The main action name (e.g., CreateUser, GetProduct, UpdateOrder)
- **{cqrs-strategy}**: The strategy description for the CQRS operation
- **{cqrs-target}Cqrs**: The target application/module (e.g., Agent, Api, Web, Mcp)

## Component Naming Strategy
- **Command**: `{cqrs-action}Command`
- **Query**: `{cqrs-action}Query`
- **Command Handler**: `{cqrs-action}CommandHandler`
- **Query Handler**: `{cqrs-action}QueryHandler`
- **Model**: `{cqrs-action}CommandPayloadModel` and `{cqrs-action}CommandResultModel`, `{cqrs-action}QueryPayloadModel` and `{cqrs-action}QueryResultModel`

## File Structure
```
*.Agent.Cqrs/
├── Injector.cs
├── Commands/
│   └── {cqrs-action}Command.cs
├── Queries/
│   └── {cqrs-action}Query.cs
├── Handlers/
│   ├── {cqrs-action}CommandHandler.cs
│   └── {cqrs-action}QueryHandler.cs
└── Models/
    └── {cqrs-action}CommandPayloadModel.cs
    └── {cqrs-action}CommandResultModel.cs
    └── {cqrs-action}QueryPayloadModel.cs
    └── {cqrs-action}QueryResultModel.cs
```

## Templates

### Command Template
```csharp
using MediatR;

namespace *.Agent.Cqrs.Commands
{
    public class {cqrs-action}Command : IRequest<{cqrs-action}CommandResultModel>
    {
        // Add properties specific to the command
        public {cqrs-action}CommandPayloadModel Payload { get; set; } = new();
    }
}
```

### Query Template
```csharp
using MediatR;

namespace *.Agent.Cqrs.Queries
{
    public class {cqrs-action}Query : IRequest<{cqrs-action}QueryResultModel>
    {
        // Add properties specific to the query
        public {cqrs-action}QueryPayloadModel Payload { get; set; } = new();
    }
}
```

### Command Handler Template
```csharp
using MediatR;
using Microsoft.Extensions.Logging;
using *.Agent.Cqrs.Commands;

namespace *.Agent.Cqrs.Handlers
{
    internal class {cqrs-action}CommandHandler(ILogger<{cqrs-action}CommandHandler> logger) : IRequestHandler<{cqrs-action}Command, {cqrs-action}CommandResultModel>
    {
        private readonly ILogger<{cqrs-action}CommandHandler> _logger = logger;

        public Task<{cqrs-action}CommandResultModel> Handle({cqrs-action}Command request, CancellationToken cancellationToken)
        {
            _logger.LogInformation("Handling {CommandName} command", nameof({cqrs-action}Command));
            
            // TODO: Implement command handling logic
            throw new NotImplementedException("Handler implementation required");
        }
    }
}
```

### Query Handler Template
```csharp
using MediatR;
using Microsoft.Extensions.Logging;
using *.Agent.Cqrs.Queries;

namespace *.Agent.Cqrs.Handlers
{
    internal class {cqrs-action}QueryHandler(ILogger<{cqrs-action}QueryHandler> logger) : IRequestHandler<{cqrs-action}Query, {cqrs-action}QueryResultModel>
    {
        private readonly ILogger<{cqrs-action}QueryHandler> _logger = logger;

        public Task<{cqrs-action}QueryResultModel> Handle({cqrs-action}Query request, CancellationToken cancellationToken)
        {
            _logger.LogInformation("Handling {QueryName} query", nameof({cqrs-action}Query));
            
            // TODO: Implement query handling logic
            throw new NotImplementedException("Handler implementation required");
        }
    }
}
```

### Model Template
```csharp
namespace *.Agent.Cqrs.Models
{
    public record {cqrs-action}CommandPayloadModel
    {
        // Add model properties
        public Guid Id { get; set; } = Guid.NewGuid();
    }
    
    public record {cqrs-action}CommandResultModel
    {
        // Add model properties
        public Guid Id { get; set; } = Guid.NewGuid();
    }

    public record {cqrs-action}QueryPayloadModel
    {
        // Add model properties
        public Guid Id { get; set; } = Guid.NewGuid();
    }
    
    public record {cqrs-action}QueryResultModel
    {
        // Add model properties
        public Guid Id { get; set; } = Guid.NewGuid();
    }
}
```

## Dependency Injection Template
```csharp
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using *.Agent.Cqrs.Handlers;

namespace *.Agent.Cqrs
{
    public static class Injector
    {
        public static IServiceCollection Add{cqrs-target}CqrsHandlers(
            this IServiceCollection services,
            IConfiguration configuration)
        {
            // Register data services
            services.InjectDataServices();

            // MediatR registration (if not already registered)
            services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(
                Assembly.GetExecutingAssembly()));

            return services;
        }
    }
}
```

## Generation Instructions

1. **Replace placeholders** with specific action names (PascalCase)
2. **File creation order**: Models → Commands/Queries → Handlers → Injector
3. **Dependencies**: MediatR library, ILogger for logging, primary constructors
4. **Namespace conventions**: Follow *.Agent.Cqrs.{Commands|Queries|Handlers|Models}
5. **Handler implementation**: Include TODO comments and NotImplementedException
6. **Async/await pattern**: Use Task<T> return types for all handlers

## Example Usage

For action "CreateUser" in "Api" target:
- Command: `CreateUserCommand`
- Query: `GetUserQuery` 
- Command Handler: `CreateUserCommandHandler`
- Query Handler: `GetUserQueryHandler`
- Model: `CreateUserCommandPayloadModel`, `CreateUserCommandResultModel`, etc.
- Target: `ApiCqrs`
EOF

# Create AGENT_ACTION_DATA.md (Data Layer Documentation)
cat > "${basepath}/agent_actions/AGENT_ACTION_DATA.md" << 'EOF'
# *.Agent.Data

This data layer provides a comprehensive repository pattern implementation for the cheshire Agent project, supporting multiple storage backends: MongoDB, In-Memory Cache, and JSON File Storage (Flash).

## Features

- **Multiple Storage Backends**: MongoDB, Memory Cache, and JSON File Storage
- **Repository Pattern**: Generic repository interfaces with specific implementations
- **Base Entity Models**: `EntityBase<T>` and `GuidEntity` with automatic timestamps
- **Paginated Queries**: Built-in support for paginated data retrieval
- **Data Streaming**: Async enumerable support for large datasets
- **Configuration-Based**: Uses shared configuration from `*.Agent/appsettings.Development.json`

## Configuration

The data layer uses configuration from `*.Agent/appsettings.Development.json`:

```json
{
  "MongoDbSettings": {
    "StreamingDelayMilliseconds": 700,
    "ConnectionString": "mongodb://edelveys:ZmeyGiryN!ch_77@localhost:27017/*_db?authSource=admin",
    "DatabaseName": "*_db"
  },
  "CachingSettings": {
    "LifetimeInMinutes": "27"
  },
  "FlashSettings": {
    "StoreDirectory": "FlashStore",
    "SerializerOptions": {
      "Encoding": "UTF-8",
      "WriteIndented": true,
      "UnsafeRelaxedJsonEscaping": true,
      "Encrypted": false
    }
  }
}
```

## Setup

### 1. Register Services

In your `Program.cs`, or `Startup.cs`, or *.Cqrs module Injector:

```csharp
using *.Agent.Data;

// Register data services
builder.Services.InjectDataServices();
```

### 2. Create Entity Models

Create entities that inherit from `GuidEntity`:

```csharp
using *.Agent.Data.Defaults;
using *.Agent.Data.Models;

[CollectionName("my_entities")]
public class MyEntity(string name, string description) : GuidEntity
{
    public required string Name { get; set; } = name;
    public required string Description { get; set; } = description;
}
```

### 3. Use Repositories

Inject and use repositories in your services:

```csharp
public class MyService(IRepositoryBuilder repositoryBuilder)
{
    private readonly IMongoRepository<MyEntity> _mongoRepo
      = repositoryBuilder.CreateMongoRepository<MyEntity>();
    private readonly ICacheRepository<MyEntity> _cacheRepo
      = repositoryBuilder.CreateCacheRepository<MyEntity>();
    private readonly IFlashRepository<MyEntity> _flashRepo
      = repositoryBuilder.CreateFlashRepository<MyEntity>();

    public async Task<MyEntity> GetEntityAsync(Guid id)
    {
        // Try cache first
        var cached = await _cacheRepo.GetByIdAsync(id);
        if (cached != null) return cached;

        // Fallback to MongoDB
        var entity = await _mongoRepo.GetByIdAsync(id);
        if (entity != null)
        {
            // Cache the result
            await _cacheRepo.InsertAsync(entity);
        }
        return entity;
    }
}
```

## Repository Types

### IMongoRepository<T>
- Full CRUD operations
- Advanced querying with expressions
- Paginated results
- Data streaming for large datasets
- Filtering and sorting

### ICacheRepository<T>
- Basic CRUD operations
- In-memory storage with configurable TTL
- Fast access for frequently used data

### IFlashRepository<T>
- JSON file-based storage
- Filtered queries with expressions
- Persistent storage without database dependency
- Suitable for configuration or small datasets

## Usage Examples

### Basic CRUD Operations

```csharp
// Create
var entity = new MyEntity("Test", "Test entity");
await _mongoRepo.InsertAsync(entity);

// Read
var retrieved = await _mongoRepo.GetByIdAsync(entity.Id);

// Update
entity.Description = "Updated description";
await _mongoRepo.UpdateAsync(entity);

// Delete
await _mongoRepo.DeleteAsync(entity);
```

### Advanced Queries

```csharp
// Get filtered list
var entities = await _mongoRepo.GetFilteredListAsync(e => e.Name.Contains("test"));

// Get paginated results
var pagedResult = await _mongoRepo.GetPagedListAsync(
    filter: e => e.CreatedAt > DateTime.Today,
    sorter: e => e.CreatedAt,
    page: 1,
    pageSize: 10,
    asc: false
);

// Stream large datasets
await foreach (var entity in _mongoRepo.StreamCollectionItemsAsync(cancellationToken))
{
    // Process each entity
    Console.WriteLine($"Processing: {entity.Name}");
}
```

## Project Structure

```
*.Agent.Data/
├── Contexts/
│   ├── MongoContext.cs      # MongoDB connection and configuration
│   ├── CacheContext.cs      # Memory cache wrapper
│   └── FlashContext.cs      # JSON file storage
├── Defaults/
│   ├── Attributes.cs        # Collection name attribute
│   └── Extensions.cs        # Helper extensions
├── Models/
│   ├── EntityBase.cs        # Base entity classes
│   ├── PagedList.cs         # Pagination support
│   └── TimespanFilter.cs    # Date filtering
├── Repos/
│   ├── Repository.cs        # Base repository interface
│   ├── RepositoryBuilder.cs # Repository factory
│   ├── MongoRepository.cs   # MongoDB implementation
│   ├── CacheRepository.cs   # Cache implementation
│   └── FlashRepository.cs   # JSON file implementation
└── Injector.cs              # Dependency injection setup
```

## Dependencies

- `Microsoft.Extensions.Caching.Memory` - For in-memory caching
- `Microsoft.Extensions.Configuration` - For configuration management
- `MongoDB.Driver` - For MongoDB connectivity
- `System.Linq` - For LINQ operations

## Base Classes

- **EntityBase<TId>**: Base class for entities with generic ID and CreatedAt timestamp
- **GuidEntity**: Extends EntityBase with Guid ID and UpdatedAt timestamp
- **PagedList<T>**: Wrapper for paginated query results
- **TimespanFilter**: Helper for date range filtering
EOF

# Add Healthchecks
add_packages "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "AspNetCore.HealthChecks.UI.Client"
add_packages "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "AspNetCore.HealthChecks.UI.Client"

# Restore, build, and watch
dotnet restore "${basepath}/${slnname}.sln"
dotnet build "${basepath}/${slnname}.sln"
dotnet watch run --project "${basepath}/${agentname}.Agent/${agentname}.Agent.csproj"

echo "All processes completed successfully."
echo "Project structure has been set up with CQRS pattern, example controllers, and MediatR integration."